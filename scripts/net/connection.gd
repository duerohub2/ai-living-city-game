extends Node

# 连接生命周期不持有房间、席位或玩法协议。调用方校验消息后才确认活跃。
signal state_changed
signal disconnected(code: int, was_open: bool)
signal text_received(text: String)

enum State { STOPPED, DISCOVERING, CONNECTING, OPEN, CLOSING, RETRY_WAIT, UNAVAILABLE }

const MAX_MESSAGE_BYTES := 4096
const DISCOVERY_SCRIPT := """
(() => {
    const page = new URL(location.href);
    const marker = page.pathname.indexOf('/__manus__/game-preview/');
    if (marker >= 0) page.pathname = page.pathname.slice(0, marker + 1);
    page.search = ''; page.hash = '';
    return new URL('multiplayer/bootstrap.json', page).href;
})()
"""

var state := State.STOPPED
var endpoint := ""
var idle_seconds := 0.0
var _socket: WebSocketPeer
var _discovery: HTTPRequest
var _generation := 0
var _make_url: Callable
var _retry_elapsed := 0.0
var _retry_delay := 0.5


func start(build: String, native_env: String, make_url: Callable) -> void:
	if OS.has_feature("web"):
		discover(str(JavaScriptBridge.eval(DISCOVERY_SCRIPT, true)), build, make_url)
		return
	var value := OS.get_environment(native_env)
	if value.is_empty() and FileAccess.file_exists("res://multiplayer/config.json"):
		var parser := JSON.new()
		parser.parse(FileAccess.get_file_as_string("res://multiplayer/config.json"))
		var config: Variant = parser.data
		if config is Dictionary and config.get("build") == build:
			value = str(config.get("signalingUrl", ""))
	connect_endpoint(value, make_url)


func discover(url: String, build: String, make_url: Callable) -> void:
	stop()
	_make_url = make_url
	_set_state(State.DISCOVERING)
	var generation := _generation
	_discovery = HTTPRequest.new()
	_discovery.timeout = 10
	_discovery.body_size_limit = 4096
	add_child(_discovery)
	_discovery.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray):
		if generation != _generation or state != State.DISCOVERING:
			return
		_discovery.queue_free()
		_discovery = null
		var parser := JSON.new()
		parser.parse(body.get_string_from_utf8())
		var config: Variant = parser.data
		if result != HTTPRequest.RESULT_SUCCESS or status != 200 or not config is Dictionary or config.get("version") != 1 or config.get("build") != build:
			_set_state(State.UNAVAILABLE)
			return
		_accept_endpoint(str(config.get("signalingUrl", "")))
	)
	if _discovery.request(url) != OK:
		_discovery.queue_free()
		_discovery = null
		_set_state(State.UNAVAILABLE)


func connect_endpoint(value: String, make_url: Callable) -> void:
	stop()
	_make_url = make_url
	_accept_endpoint(value)


func _accept_endpoint(value: String) -> void:
	var pattern := RegEx.new()
	pattern.compile("^wss://[^/@?#:]+(:[0-9]+)?/ws$|^ws://(127\\.0\\.0\\.1|localhost|\\[::1\\])(:[0-9]+)?/ws$")
	if pattern.search(value) == null or not _make_url.is_valid():
		_set_state(State.UNAVAILABLE)
		return
	endpoint = value
	_connect_socket()


func _connect_socket() -> void:
	idle_seconds = 0.0
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = 65536
	_socket.outbound_buffer_size = 8192
	_socket.max_queued_packets = 64
	state = State.CONNECTING
	var error := _socket.connect_to_url(str(_make_url.call(endpoint)))
	if error != OK:
		reconnect()
		return
	state_changed.emit()


# 由宿主游戏每帧调用；配置等待不推进 socket 超时或重试。
func poll(delta: float) -> void:
	if state == State.RETRY_WAIT:
		_retry_elapsed += delta
		if _retry_elapsed >= _retry_delay:
			_connect_socket()
		return
	if state not in [State.CONNECTING, State.OPEN, State.CLOSING] or _socket == null:
		return
	var generation := _generation
	_socket.poll()
	var socket_state := _socket.get_ready_state()
	if socket_state == WebSocketPeer.STATE_CLOSED:
		reconnect(_socket.get_close_code())
		return
	if socket_state == WebSocketPeer.STATE_CLOSING and state != State.CLOSING:
		_set_state(State.CLOSING)
	if socket_state == WebSocketPeer.STATE_OPEN:
		if state != State.OPEN:
			_retry_delay = 0.5
			_set_state(State.OPEN)
		while generation == _generation and _socket != null and _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			if _socket.was_string_packet() and packet.size() <= MAX_MESSAGE_BYTES:
				text_received.emit(packet.get_string_from_utf8())
	if generation != _generation:
		return
	idle_seconds += delta
	if idle_seconds > 10.0:
		reconnect(4000)


func confirm_activity() -> void:
	idle_seconds = 0.0


func send_text(text: String) -> Error:
	if state != State.OPEN or _socket == null:
		return ERR_UNAVAILABLE
	return _socket.send_text(text)


func reconnect(code: int = 1000) -> void:
	if state not in [State.CONNECTING, State.OPEN, State.CLOSING]:
		return
	var was_open := state == State.OPEN
	_close_socket(code, "reconnect")
	_generation += 1
	_retry_elapsed = 0.0
	_retry_delay = minf(4.0, _retry_delay * 1.65)
	_set_state(State.RETRY_WAIT)
	disconnected.emit(code, was_open)


func stop(code: int = 1000, reason: String = "leave") -> void:
	_generation += 1
	if _discovery != null:
		_discovery.cancel_request()
		_discovery.queue_free()
		_discovery = null
	_close_socket(code, reason)
	endpoint = ""
	idle_seconds = 0.0
	_retry_delay = 0.5
	_retry_elapsed = 0.0
	_set_state(State.STOPPED)


func _close_socket(code: int, reason: String) -> void:
	if _socket != null:
		if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
			_socket.close(code, reason)
		_socket = null


func _set_state(value: State) -> void:
	state = value
	state_changed.emit()


func _exit_tree() -> void:
	stop()
