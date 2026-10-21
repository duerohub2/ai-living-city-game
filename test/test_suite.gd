extends Node

const ProtocolType := preload("res://scripts/net/protocol.gd")
const MotionType := preload("res://scripts/game/local_paddle.gd")
const BoardType := preload("res://scripts/game/pong_board.gd")

var _failures := PackedStringArray()
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	# First-launch language follows the machine locale; pin English so checks are machine-independent.
	I18n.set_locale("en")
	_test_locale_detection()
	_test_identity_and_inputs()
	_test_project_font()
	_test_protocol()
	_test_anticipation()
	await _test_board()
	await _test_main_scene()
	await _test_connection_validation()
	_test_localization()
	_test_audio()
	AudioDirector.release_streams()
	await get_tree().process_frame
	if _failures.is_empty():
		print("[pong-tests] PASS: %d checks" % _checks)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[pong-tests] " + failure)
	print("[pong-tests] FAIL: %d failures across %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)


func _test_locale_detection() -> void:
	# Pure functions only: results must not depend on this machine's OS locale.
	var i18n_script: Script = load("res://autoload/i18n.gd")
	for case: Array in [
		["zh_CN", "zh-CN"], ["zh-CN", "zh-CN"], ["zh-Hans-CN", "zh-CN"], ["zh_TW", "zh-CN"], ["ZH", "zh-CN"],
		["en_US", "en"], ["en", "en"], ["fr_FR", "en"], ["ja_JP", "en"], ["", "en"],
	]:
		_check(i18n_script.call("detect_locale", case[0]) == case[1], "OS locale %s must map to %s" % case)
	_check(i18n_script.call("resolve_locale", "", "zh_CN") == "zh-CN", "first launch follows a Chinese browser")
	_check(i18n_script.call("resolve_locale", "", "de_DE") == "en", "first launch defaults other languages to English")
	_check(i18n_script.call("resolve_locale", "en", "zh_CN") == "en", "a saved English choice beats a Chinese browser")
	_check(i18n_script.call("resolve_locale", "zh-CN", "en_US") == "zh-CN", "a saved Chinese choice beats an English browser")
	_check(i18n_script.call("resolve_locale", "xx", "en_US") == "en", "unknown saved values fall back to detection")


func _test_identity_and_inputs() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "Multiplayer Paddle Game", "project identity")
	_check(InputMap.has_action("move_up") and InputMap.has_action("move_down"), "vertical movement actions")
	_check(not InputMap.has_action("move_left") and not InputMap.has_action("move_right"), "A and D remain unassigned")
	_check(get_tree().root.has_node("TuningStore"), "TuningStore autoload")
	_check(get_tree().root.has_node("AudioDirector"), "AudioDirector autoload")
	_check(get_tree().root.has_node("SaveStore"), "locale preference service")
	_check(get_tree().root.has_node("I18n"), "template localization restored")


func _test_project_font() -> void:
	# This label is outside main.gd's subtree: the project default must cover it too.
	var label := Label.new()
	add_child(label)
	var font := label.get_theme_font("font")
	var expected := load("res://assets/template/fonts/ui_regular.tres") as Font
	_check(font == expected, "unrelated Control inherits project-wide composite font")
	_check(font.has_char(0x4e2d), "project-wide font supports Chinese through its fallback")
	label.queue_free()


func _test_protocol() -> void:
	_check(ProtocolType.parse_packet("not json").is_empty(), "invalid JSON rejected")
	_check(ProtocolType.parse_packet('{"type":"unknown"}').is_empty(), "unknown message rejected")
	var error := {"type": "error", "marker": ProtocolType.BUILD, "room": "ABCD", "code": "invalid_message"}
	_check(not ProtocolType.decode(JSON.stringify(error), "ABCD", 7).is_empty(), "scoped server error accepted")
	_check(ProtocolType.decode(JSON.stringify(error), "OTHER", 7).is_empty(), "cross-room error rejected")
	error.code = "unrecognized"
	_check(ProtocolType.decode(JSON.stringify(error), "ABCD", 7).is_empty(), "unknown error code rejected")
	var packet := {"type": "state", "marker": "pong-online-v2", "room": "ABCD", "seq": 7, "phase": "live", "players": {"left": true, "right": true}, "ball": {"x": 0.5, "y": 0.5}, "paddles": {"left": {"y": 0.2, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, "right": {"y": 0.8, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}}, "score": {"left": 3, "right": 4}, "event": {"seq": 2, "kind": "score"}}
	_check(not ProtocolType.decode(JSON.stringify(packet), "ABCD", 6).is_empty(), "valid authority snapshot")
	_check(ProtocolType.decode(JSON.stringify(packet), "ABCD", 7).is_empty(), "stale snapshot rejected")
	_check(ProtocolType.decode(JSON.stringify(packet), "OTHER", 6).is_empty(), "cross-room snapshot rejected")
	packet.paddles.left.vy = "invalid"
	_check(ProtocolType.decode(JSON.stringify(packet), "ABCD", 6).is_empty(), "invalid velocity rejected")
	packet.paddles.left.vy = 0.0
	packet.paddles.left.ack_seq = -1
	_check(ProtocolType.decode(JSON.stringify(packet), "ABCD", 6).is_empty(), "invalid input acknowledgement rejected")
	packet.paddles.left.ack_seq = 0
	packet.ball.x = "invalid"
	_check(ProtocolType.decode(JSON.stringify(packet), "ABCD", 6).is_empty(), "invalid number rejected")
	_check(ProtocolType.valid_room("ABCD") and not ProtocolType.valid_room("A/B"), "room grammar")



func _test_anticipation() -> void:
	var motion = MotionType.new()
	motion.configure({"speed": 0.74, "min_y": 0.11, "max_y": 0.89})
	motion.accept({"y": 0.5, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, true, 1, 1000)
	motion.set_input(1.0, 1)
	_check(motion.advance(1.0 / 60.0) > 0.51, "owned paddle moves before any input acknowledgement")
	var before: float = motion.y
	motion.set_input(0.0, 2)
	motion.accept({"y": 0.5, "vy": 0.74, "ack_seq": 1, "sent_msec": 900}, true, 2, 1100)
	_check(is_equal_approx(motion.advance(1.0 / 60.0), before), "old moving snapshot cannot undo local stop")
	motion.set_input(-1.0, 3)
	_check(motion.advance(1.0 / 60.0) < before - 0.01, "reverse responds before server confirmation")
	motion.set_input(0.0, 4)
	motion.accept({"y": 0.54, "vy": 0.0, "ack_seq": 4, "sent_msec": 1000}, true, 3, 1200)
	before = motion.y
	var corrected: float = motion.advance(1.0 / 60.0)
	_check(corrected > before and corrected < 0.54, "small error blends instead of snapping")
	motion.accept({"y": 0.88, "vy": 0.0, "ack_seq": 4, "sent_msec": 1000}, true, 4, 1200)
	_check(is_equal_approx(motion.advance(1.0 / 60.0), 0.88), "large divergence resets promptly")
	motion.accept({"y": 0.2, "vy": 0.0, "ack_seq": 4, "sent_msec": 1000}, true, 3, 1200)
	_check(motion.advance(1.0 / 60.0) > 0.8, "stale snapshot cannot move local paddle")
	motion.set_input(1.0, 5)
	motion.advance(0.05)
	_check(motion.y <= 0.89, "anticipation respects server movement bounds")
	motion.advance(0.6)
	_check(not motion.active and is_equal_approx(motion.y, 0.88), "stale connection stops anticipation and clears drift")
	motion.accept({"y": 0.3, "vy": 0.0, "ack_seq": 5, "sent_msec": 1100}, false, 5, 1300)
	_check(is_equal_approx(motion.advance(0.1), 0.3), "waiting phase cannot anticipate movement")
	motion.reset()
	_check(not motion.initialized and not motion.active, "disconnect clears prediction and timing")
	motion.accept({"y": 0.4, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, true, 1, 1500)
	_check(is_equal_approx(motion.y, 0.4), "reconnect accepts new sequence and authoritative position")
	for step in 40:
		motion.set_input(1.0 if step % 2 == 0 else -1.0, step + 1)
		motion.accept({"y": 0.4, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, true, step + 2, 1500 + step * 17)
		motion.advance(1.0 / 60.0)
	_check(motion.get("_pending_age") > 0.5, "rapid direction changes cannot extend correction deferral forever")
	motion.reset()
	motion.accept({"y": 0.4, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, true, 1, 1500)
	# A rejected change must eventually reconcile even when other snapshots keep arriving.
	motion.set_input(1.0, 1)
	for step in 90:
		motion.accept({"y": 0.4, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, true, step + 2, 1600 + step * 17)
		motion.advance(1.0 / 60.0)
	motion.set_input(0.0, 2)
	for step in 150:
		motion.accept({"y": 0.4, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, true, step + 100, 3200 + step * 17)
		motion.advance(1.0 / 60.0)
	_check(absf(motion.y - 0.4) < 0.003, "unacknowledged/rejected input eventually converges")


func _test_board() -> void:
	var board: PongBoard = BoardType.new()
	board.size = Vector2(960.0, 540.0)
	add_child(board)
	board.apply_snapshot({
		"phase": "live", "ball": {"x": 0.25, "y": 0.75},
		"paddles": {"left": {"y": 0.3}, "right": {"y": 0.7}},
		"event": {"seq": 1, "kind": "paddle"},
	})
	await get_tree().process_frame
	var state: Dictionary = board.get_debug_state()
	_check(state.ball == Vector2(0.25, 0.75), "board consumes server ball")
	_check(is_equal_approx(float(state.left), 0.3) and is_equal_approx(float(state.right), 0.7), "board consumes both paddles")
	_check(str(state.phase) == "live", "board consumes phase")
	board.queue_free()
	await get_tree().process_frame


func _test_main_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		return
	var main := packed.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.debug_apply_snapshot({
		"type": "state", "seq": 12, "phase": "live", "role": "left",
		"ball": {"x": 0.6, "y": 0.4},
		"paddles": {"left": {"y": 0.2, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, "right": {"y": 0.8, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}},
		"score": {"left": 3, "right": 2},
		"event": {"seq": 1, "kind": "score"},
	})
	await get_tree().process_frame
	_check((main.get("_score_label") as Label).text == "3   2", "shared score rendered")
	_check("LIVE" in (main.get("_status_label") as Label).text, "connection state rendered")
	_check((main.get("_board") as PongBoard).get_debug_state().ball == Vector2(0.6, 0.4), "main forwards authority snapshot")
	main.set("_role", "spectator")
	main._refresh_connection_label("waiting")
	_check(main.get("_status_key") == "spectator.waiting", "waiting spectators receive manual seat retry guidance")
	main._handle_packet(JSON.stringify({"type": "error", "marker": ProtocolType.BUILD, "room": main.get("_room_code"), "code": "invalid_message"}))
	_check(main.get("_status_key") == "service.error" and not main.get("_playing"), "server rejection shows a stable reconnect state")
	_check("Please reconnect" in (main.get("_status_label") as Label).text, "server rejection uses player-facing localized copy")
	main.queue_free()
	await get_tree().process_frame


func _test_connection_validation() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	main.set_process(false)
	main.set("_room_code", "ABCD")
	main.set("_playing", true)
	var listener := TCPServer.new()
	_check(listener.listen(0, "127.0.0.1") == OK, "local validation server starts")
	main.get("_connection").connect_endpoint("ws://127.0.0.1:%d/ws" % listener.get_local_port(), main._websocket_url)
	var peer := WebSocketPeer.new()
	var accepted := false
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if not accepted and listener.is_connection_available():
			accepted = peer.accept_stream(listener.take_connection()) == OK
		if accepted:
			peer.poll()
		main.get("_connection").poll(0.0)
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN and main.get("_connection").state == main.ConnectionType.State.OPEN:
			break
		await get_tree().process_frame
	_check(peer.get_ready_state() == WebSocketPeer.STATE_OPEN, "validation WebSocket opens")
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		main.queue_free()
		listener.stop()
		return
	main.get("_connection").idle_seconds = 9.0
	peer.send_text("not json")
	peer.put_packet(PackedByteArray([1, 2, 3]))
	peer.send_text("x".repeat(ProtocolType.MAX_MESSAGE_BYTES + 1))
	await _pump_validation_socket(main, peer)
	_check(main.get("_connection").idle_seconds == 9.0, "invalid, binary and oversized packets do not refresh timeout")
	var welcome := {"type": "welcome", "marker": ProtocolType.BUILD, "room": "ABCD", "role": "left", "resume_token": "0123456789abcdef", "movement": {"speed": 0.74, "min_y": 0.11, "max_y": 0.89}}
	peer.send_text(JSON.stringify(welcome))
	await _pump_validation_socket(main, peer)
	_check(main.get("_has_welcome") and main.get("_connection").idle_seconds == 0.0, "valid welcome activates connection and refreshes timeout")
	var state := {"type": "state", "marker": ProtocolType.BUILD, "room": "ABCD", "seq": 1, "phase": "live", "players": {"left": true, "right": true}, "paddles": {"left": {"y": 0.5, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}, "right": {"y": 0.5, "vy": 0.0, "ack_seq": 0, "sent_msec": 0}}, "ball": {"x": 0.5, "y": 0.5}, "score": {"left": 0, "right": 0}, "event": {"seq": 0, "kind": ""}}
	peer.send_text(JSON.stringify(state))
	await _pump_validation_socket(main, peer)
	var board = main.get("_board")
	board.set_process(false)
	Input.action_press("move_down")
	main._process(1.0 / 60.0)
	board._process(1.0 / 60.0)
	_check(board.get_debug_state().visual_left > 0.51 and board.get_debug_state().left == 0.5, "real scene renders input before server responds")
	_check(board.get_debug_state().visual_right == 0.5, "local input never anticipates opponent")
	Input.action_release("move_down")
	var stopped: float = board.get_debug_state().visual_left
	main._process(1.0 / 60.0)
	board._process(1.0 / 60.0)
	_check(is_equal_approx(board.get_debug_state().visual_left, stopped), "real scene stops before server responds")
	welcome.marker = "pong-online-v1"
	welcome.room = "OTHER"
	main.get("_connection").idle_seconds = 9.0
	peer.send_text(JSON.stringify(welcome))
	await _pump_validation_socket(main, peer)
	_check(main.get("_playing") and main.get("_connection").idle_seconds == 9.0, "cross-room packet neither rejects connection nor refreshes timeout")
	welcome.room = "ABCD"
	# Queue more than one incompatible packet to exercise closing inside the receive loop.
	peer.send_text(JSON.stringify(welcome))
	peer.send_text(JSON.stringify(welcome))
	await _pump_validation_socket(main, peer)
	_check(main.get("_connection").state == main.ConnectionType.State.STOPPED and not main.get("_has_welcome"), "incompatible server closes connection and clears seat authority")
	_check(not main.get("_playing") and main.get("_status_key") == "protocol.mismatch", "incompatible server stops automatic reconnection with actionable status")
	main._process(20.0)
	_check(main.get("_connection").state == main.ConnectionType.State.STOPPED and main.get("_status_key") == "protocol.mismatch", "later frames preserve version error without reconnecting")
	I18n.set_locale("zh-CN")
	_check("刷新" in (main.get("_status_label") as Label).text, "version error recovery is localized")
	I18n.set_locale("en")
	_check("Reload" in (main.get("_status_label") as Label).text, "version error gives reload instruction")
	main._leave_room()
	_check((main.get("_menu") as Control).visible, "player can leave after protocol rejection")
	main.queue_free()
	peer.close()
	listener.stop()
	await get_tree().process_frame


func _pump_validation_socket(main: Node, peer: WebSocketPeer) -> void:
	for _index in 12:
		peer.poll()
		main.get("_connection").poll(0.0)
		await get_tree().process_frame


func _test_audio() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	AudioDirector.unlock_audio()
	_check(AudioDirector.play_music("music.gameplay"), "one procedural BGM registered")
	for cue: String in ["ui.confirm", "ui.cancel", "player.action", "enemy.impact", "score.reward"]:
		_check(AudioDirector.play_cue(cue), "procedural cue registered: " + cue)
	main.queue_free()


func _check(condition: bool, context: String) -> void:
	_checks += 1
	if not condition and context not in _failures:
		_failures.append(context)

func _test_localization() -> void:
	var en := I18n.catalog_keys("en")
	var cn := I18n.catalog_keys("zh-CN")
	en.sort()
	cn.sort()
	_check(en == cn, "locale key parity")
	I18n.set_locale("zh-CN")
	_check(I18n.t("play") != "play", "Chinese title copy")
	I18n.set_locale("en")
	_check(I18n.t("live") == "LIVE", "English restoration")
