extends Control
const OpenSourceLicenses = preload("res://scripts/manus/open_source_licenses.gd")

const PongBoardType := preload("res://scripts/game/pong_board.gd")
const ProtocolType := preload("res://scripts/net/protocol.gd")

const COLOR_BG := Color("071018")
const COLOR_TEXT := Color("f2f7ff")
const COLOR_MUTED := Color("7f91a3")
const COLOR_ONLINE := Color("59e1c2")
const COLOR_WAITING := Color("f1c75b")
const COLOR_OFFLINE := Color("ff6b73")
const COLOR_INK := Color("041017")
const COLOR_LINE := Color("1c3444")
const COLOR_P2 := Color("ff5fa2")
const FONT_REGULAR := "res://assets/template/fonts/ui_regular.tres"
const FONT_MEDIUM := "res://assets/template/fonts/ui_medium.tres"
const FONT_TITLE := "res://assets/template/fonts/display/pong_title.tres"
const FONT_TITLE_TRACKED := "res://assets/template/fonts/display/pong_title_tracked.tres"
const FONT_CODE := "res://assets/template/fonts/display/pong_code.tres"
const FONT_SCORE := "res://assets/template/fonts/display/pong_score.tres"
const FONT_CAPTION := "res://assets/template/fonts/display/pong_caption.tres"
const SEND_INTERVAL := 0.05
const ConnectionType := preload("res://scripts/net/connection.gd")
const NeonTextType := preload("res://scripts/ui/neon_text.gd")
const AttractCourtType := preload("res://scripts/ui/attract_court.gd")
const ScoreboardType := preload("res://scripts/ui/scoreboard.gd")
const CRT_SHADER := preload("res://shaders/crt_overlay.gdshader")

var _connection := ConnectionType.new()
var _room_code := ""
var _role := "spectator"
var _resume_token := ""
var _last_snapshot_seq := -1
var _last_event_seq := -1
var _input_seq := 0
var _last_sent_axis := 99.0
var _send_elapsed := 0.0
var _pointer_axis := 0.0
var _pointer_active := false
var _music_started := false
var _has_welcome := false
var _playing := false
var _focused := true
var _settings_controls: Dictionary = {}
var _languages: HBoxContainer
var _menu: VBoxContainer
var _room_input: LineEdit
var _hint: Label
var _toolbar: HBoxContainer
var _status_key := "connecting"
var _status_color := COLOR_WAITING
var _phase := "waiting"
var _labels: Dictionary = {}
var _captions: Dictionary = {}
var _title_main: Label
var _title_sub: Label

var _board: PongBoard
var _status_label: Label
var _room_label: Label
var _score_label: Label
# Round-3 arcade presentation layer.
var _attract: Control
var _brand: VBoxContainer
var _lobby: PanelContainer
var _attract_prompt: Label
var _play_button: Button
var _scoreboard: Control
var _status_dot: Panel
var _court_banner: Label
var _shutter: Control
var _shutter_progress := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_connection)
	_connection.text_received.connect(_handle_packet)
	_connection.state_changed.connect(_connection_state_changed)
	_connection.disconnected.connect(_connection_lost)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	_apply_presentation()
	TuningStore.value_changed.connect(func(_id: String, _requested: Variant, _active: Variant): _apply_presentation(); _sync_settings_controls())
	_register_procedural_audio()
	_room_code = _resolve_room_code()
	_room_input.text = _room_code
	I18n.locale_changed.connect(func(_locale: String): _refresh_language())
	_refresh_language()
	_show_menu()


func _process(delta: float) -> void:
	_connection.poll(delta)
	if not _playing:
		return
	if _has_welcome and _connection.idle_seconds > 0.5:
		_set_status("reconnecting", COLOR_WAITING)
	if _connection.state == ConnectionType.State.OPEN:
		_send_elapsed += delta
		var axis := _current_axis()
		_board.set_local_input(axis, _input_seq + 1)
		if _has_welcome and _role in ["left", "right"] and _send_elapsed >= SEND_INTERVAL:
			_send_elapsed = 0.0
			_send_input(axis)


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch:
		AudioDirector.unlock_audio()
		_start_music()
	if event is InputEventScreenTouch:
		_pointer_active = event.pressed and _board.get_global_rect().has_point(event.position)
		_pointer_axis = _axis_for_pointer(event.position.y) if _pointer_active else 0.0
	elif event is InputEventScreenDrag and _pointer_active:
		_pointer_axis = _axis_for_pointer(event.position.y)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer_active = event.pressed and _board.get_global_rect().has_point(event.position)
		_pointer_axis = _axis_for_pointer(event.position.y) if _pointer_active else 0.0
	elif event is InputEventMouseMotion and _pointer_active and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_pointer_axis = _axis_for_pointer(event.position.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_pointer_active = false
		_pointer_axis = 0.0
		if is_instance_valid(_board):
			_board.set_local_input(0.0, _input_seq + 1)
		_send_input(0.0)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_board = PongBoardType.new()
	_board.name = "PongBoard"
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.offset_left = 24.0
	_board.offset_top = 82.0
	_board.offset_right = -24.0
	_board.offset_bottom = -72.0
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)

	# Status pill: sized to its text, border tinted by connection state in _set_status().
	_status_label = _make_label(14, COLOR_WAITING, "res://assets/template/fonts/ui_bold.tres")
	_status_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status_label.position = Vector2(24.0, 24.0)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	_status_label.add_theme_constant_override("line_spacing", 2)
	var pill := _box(Color(0.02, 0.06, 0.09, 0.92), Color(COLOR_WAITING, 0.5), 16, 2)
	pill.shadow_color = Color(COLOR_WAITING, 0.18)
	pill.shadow_size = 10
	pill.content_margin_left = 32.0
	pill.content_margin_right = 14.0
	pill.content_margin_top = 7.0
	pill.content_margin_bottom = 6.0
	_status_label.add_theme_stylebox_override("normal", pill)
	add_child(_status_label)

	_room_label = _make_label(15, COLOR_MUTED, FONT_MEDIUM)
	_room_label.anchor_left = 0.55
	_room_label.anchor_top = 0.0
	_room_label.anchor_right = 1.0
	_room_label.anchor_bottom = 0.0
	_room_label.offset_left = 6.0
	_room_label.offset_top = 24.0
	_room_label.offset_right = -26.0
	_room_label.offset_bottom = 56.0
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_room_label.add_theme_color_override("font_color", Color("9fded0"))
	_room_label.add_theme_font_override("font", load(FONT_CAPTION))
	_room_label.add_theme_font_size_override("font_size", 13)
	add_child(_room_label)

	_score_label = _make_label(50, COLOR_TEXT, FONT_SCORE)
	_score_label.anchor_left = 0.25
	_score_label.anchor_top = 0.0
	_score_label.anchor_right = 0.75
	_score_label.anchor_bottom = 0.0
	_score_label.offset_top = 8.0
	_score_label.offset_bottom = 78.0
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_score_label.text = "0   0"
	# The Label keeps the authoritative text; the versus scoreboard child presents it.
	_score_label.self_modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_score_label)
	_scoreboard = ScoreboardType.new()
	_score_label.add_child(_scoreboard)
	_status_dot = Panel.new()
	var dot_style := _box(Color.WHITE, Color.WHITE, 5, 0)
	dot_style.shadow_color = Color(1.0, 1.0, 1.0, 0.4)
	dot_style.shadow_size = 6
	_status_dot.add_theme_stylebox_override("panel", dot_style)
	_status_dot.size = Vector2(10.0, 10.0)
	_status_dot.position = Vector2(14.0, 0.0)
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_child(_status_dot)
	_status_label.resized.connect(func() -> void: _status_dot.position.y = (_status_label.size.y - 10.0) * 0.5)
	_start_blink(_status_dot, 1.2)
	_court_banner = NeonTextType.new()
	_court_banner.add_theme_font_override("font", load(FONT_CAPTION))
	_court_banner.add_theme_font_size_override("font_size", 30)
	_court_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_court_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_court_banner.offset_left = -560.0
	_court_banner.offset_right = 560.0
	_court_banner.offset_top = -170.0
	_court_banner.offset_bottom = -110.0
	_court_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_court_banner.visible = false
	_board.add_child(_court_banner)
	_start_blink(_court_banner, 1.6)
	_build_menu()
	_shutter = Control.new()
	_shutter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shutter.z_index = 90
	_shutter.visible = false
	_shutter.draw.connect(_draw_shutter)
	add_child(_shutter)
	var crt := ColorRect.new()
	crt.color = Color.WHITE
	crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crt.z_index = 85
	var crt_material := ShaderMaterial.new()
	crt_material.shader = CRT_SHADER
	crt_material.set_shader_parameter("motion", 0.0 if bool(TuningStore.get_value("ui.reduced_motion", false)) else 1.0)
	crt.material = crt_material
	add_child(crt)


func _make_label(font_size: int, color: Color, font_path: String = "") -> Label:
	var label := Label.new()
	if font_path.is_empty():
		font_path = "res://assets/template/fonts/ui_bold.tres" if font_size >= 40 else FONT_MEDIUM
	label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _connection_state_changed() -> void:
	if _connection.state in [ConnectionType.State.DISCOVERING, ConnectionType.State.CONNECTING, ConnectionType.State.OPEN]:
		_has_welcome = false
		_set_status("connecting", COLOR_WAITING)
	elif _connection.state == ConnectionType.State.CLOSING:
		_board.stop_local()
		_has_welcome = false
		_set_status("reconnecting", COLOR_WAITING)
	elif _connection.state == ConnectionType.State.UNAVAILABLE:
		_set_status("service.missing", COLOR_OFFLINE)


func _connection_lost(code: int, was_open: bool) -> void:
	_board.stop_local()
	_has_welcome = false
	if code == 4001:
		_playing = false
		_connection.stop()
		_set_status("offline", COLOR_OFFLINE)
		return
	if was_open:
		AudioDirector.play_cue("ui.cancel")
	_set_status("reconnecting", COLOR_OFFLINE)


func _websocket_url(endpoint: String) -> String:
	if OS.has_feature("web"):
		_resume_token = _load_resume_token(_room_code)
	var url := endpoint + "?room=" + _room_code.uri_encode()
	if not _resume_token.is_empty():
		url += "&resume=" + _resume_token.uri_encode()
	return url


func _handle_packet(text: String) -> void:
	var header := ProtocolType.parse_packet(text)
	if header.get("type") in ["welcome", "state"] and header.get("room") == _room_code and header.get("marker") is String and header.marker != ProtocolType.BUILD:
		_reject_protocol()
		return
	var message := ProtocolType.decode(text, _room_code, _last_snapshot_seq)
	if message.is_empty():
		return
	match str(message.get("type", "")):
		"welcome":
			_connection.confirm_activity()
			_score_label.show()
			_role = str(message.get("role", "spectator"))
			_resume_token = str(message.get("resume_token", ""))
			_has_welcome = true
			_last_snapshot_seq = -1
			_last_event_seq = -1
			_input_seq = 0
			_board.configure_local(_role, message.movement)
			_last_sent_axis = 99.0
			_store_resume_token()
			AudioDirector.play_cue("ui.confirm")
			_refresh_connection_label("waiting")
		"state":
			if not _has_welcome:
				return
			var snapshot := ProtocolType.normalize_state(message)
			var seq := int(snapshot.get("seq", -1))
			if snapshot.is_empty() or seq <= _last_snapshot_seq:
				return
			_connection.confirm_activity()
			_last_snapshot_seq = seq
			_board.apply_snapshot(snapshot)
			_update_score(snapshot.get("score", {}))
			_refresh_connection_label(str(snapshot.get("phase", "waiting")))
			_handle_audio_event(snapshot)
		"error":
			_reject_protocol("service.error")


func _reject_protocol(status_key: String = "protocol.mismatch") -> void:
	_board.stop_local()
	_playing = false
	_has_welcome = false
	_pointer_active = false
	_pointer_axis = 0.0
	_connection.stop(1002, "protocol rejected")
	_score_label.hide()
	_set_status(status_key, COLOR_OFFLINE)


func _send_input(axis: float) -> void:
	if not _has_welcome or _role not in ["left", "right"] or _connection.state != ConnectionType.State.OPEN:
		return
	_input_seq += 1
	_last_sent_axis = axis
	var payload := JSON.stringify({"type": "input", "value": axis, "seq": _input_seq, "sent_msec": Time.get_ticks_msec()})
	_connection.send_text(payload)


func _current_axis() -> float:
	if not _focused or not _playing:
		return 0.0
	var keyboard := Input.get_axis("move_up", "move_down")
	if absf(_pointer_axis) > absf(keyboard):
		return _pointer_axis
	return keyboard


func _axis_for_pointer(pointer_y: float) -> float:
	var rect := _board.get_global_rect()
	if pointer_y < rect.position.y or pointer_y > rect.end.y:
		return 0.0
	return -1.0 if pointer_y < rect.get_center().y else 1.0


func _update_score(score_value: Variant) -> void:
	if typeof(score_value) != TYPE_DICTIONARY:
		return
	var score: Dictionary = score_value
	_score_label.text = "%d   %d" % [int(score.get("left", 0)), int(score.get("right", 0))]


func _refresh_connection_label(phase: String) -> void:
	_phase = phase
	if not _has_welcome:
		return
	_set_status(("spectator.waiting" if phase == "waiting" else "spectator") if _role == "spectator" else phase, COLOR_ONLINE if phase == "live" else COLOR_WAITING)

func _set_status(key: String, color: Color) -> void:
	_status_key = key
	_status_color = color
	if _status_label != null:
		_status_label.text = I18n.t(key)
		if _has_welcome:
			_status_label.text += " / " + I18n.t("role." + _role)
		_status_label.add_theme_color_override("font_color", color)
		var pill := _status_label.get_theme_stylebox("normal") as StyleBoxFlat
		if pill != null:
			pill.border_color = Color(color, 0.6)
			pill.shadow_color = Color(color, 0.18)
		_room_label.text = I18n.t("room") + "  " + _room_code
	if _status_dot != null:
		_status_dot.self_modulate = color
		(_status_dot.get_theme_stylebox("panel") as StyleBoxFlat).shadow_color = Color(color, 0.5)
	if _scoreboard != null:
		_scoreboard.set("local_role", _role if _has_welcome else "spectator")
		_scoreboard.set("you_text", I18n.t("you"))
	if _court_banner != null:
		_court_banner.text = I18n.t(key).split("\n")[0]
		_court_banner.set("glow", color)
		_court_banner.visible = key not in ["live", "spectator"]


func _handle_audio_event(snapshot: Dictionary) -> void:
	var event_value: Variant = snapshot.get("event", {})
	if typeof(event_value) != TYPE_DICTIONARY:
		return
	var event: Dictionary = event_value
	var seq := int(event.get("seq", -1))
	if _last_event_seq < 0:
		_last_event_seq = seq
		return
	if seq <= _last_event_seq:
		return
	_last_event_seq = seq
	match str(event.get("kind", "")):
		"paddle": AudioDirector.play_cue("player.action")
		"wall": AudioDirector.play_cue("enemy.impact")
		"score": AudioDirector.play_cue("score.reward")


func _resolve_room_code() -> String:
	var requested := _sanitize_room(_query_parameter("room") if OS.has_feature("web") else OS.get_environment("PONG_ROOM"))
	if requested.length() >= 4:
		_resume_token = _load_resume_token(requested)
		return requested
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var generated := ""
	for _index: int in 6:
		generated += alphabet.substr(rng.randi_range(0, alphabet.length() - 1), 1)
	if OS.has_feature("web"):
		_write_room_url(generated)
	_resume_token = _load_resume_token(generated)
	return generated


func _sanitize_room(value: String) -> String:
	var allowed := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var result := ""
	for index: int in mini(value.length(), 8):
		var character := value.substr(index, 1).to_upper()
		if character in allowed:
			result += character
	return result


func _query_parameter(name: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var script := "new URLSearchParams(location.search).get('%s') || ''" % name
	return str(JavaScriptBridge.eval(script, true))


func _load_resume_token(room: String) -> String:
	if not OS.has_feature("web") or _connection.endpoint.is_empty():
		return ""
	var raw := str(JavaScriptBridge.eval("(() => { try { return sessionStorage.getItem('pong_resume_%s') || ''; } catch { return ''; } })()" % room, true))
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary:
		return ""
	if parser.data.get("endpoint") != _connection.endpoint:
		return ""
	return str(parser.data.get("token", ""))

func _store_resume_token() -> void:
	if OS.has_feature("web"):
		var key := JSON.stringify("pong_resume_" + _room_code)
		var value := JSON.stringify(JSON.stringify({"endpoint": _connection.endpoint, "token": _resume_token}))
		JavaScriptBridge.eval("(() => { try { sessionStorage.setItem(%s, %s); } catch {} })()" % [key, value], true)

func _write_room_url(room: String) -> void:
	JavaScriptBridge.eval("(() => { const u = new URL(location.href); u.searchParams.set('room', %s); u.searchParams.delete('ws'); history.replaceState(null, '', u); })()" % JSON.stringify(room), true)


func _register_procedural_audio() -> void:
	var music := _make_music_stream()
	AudioDirector.register_stream("music.gameplay", music)
	AudioDirector.register_stream("ui.confirm", _make_tone_stream(660.0, 0.10, 0.16))
	AudioDirector.register_stream("ui.cancel", _make_tone_stream(180.0, 0.16, 0.18))
	AudioDirector.register_stream("player.action", _make_tone_stream(420.0, 0.055, 0.20))
	AudioDirector.register_stream("enemy.impact", _make_tone_stream(260.0, 0.05, 0.16))
	AudioDirector.register_stream("score.reward", _make_tone_stream(880.0, 0.22, 0.22))
	AudioDirector.register_stream("game.victory", _make_tone_stream(880.0, 0.22, 0.22))
	AudioDirector.register_stream("game.defeat", _make_tone_stream(180.0, 0.16, 0.18))


func _start_music() -> void:
	if _music_started:
		return
	_music_started = AudioDirector.play_music("music.gameplay", 0.2)


func _make_tone_stream(frequency: float, duration: float, amplitude: float) -> AudioStreamWAV:
	var rate := 16000
	var count := int(duration * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index: int in count:
		var t := float(index) / float(rate)
		var envelope := pow(maxf(0.0, 1.0 - t / duration), 2.0)
		var sample := int(sin(TAU * frequency * t) * amplitude * envelope * 32767.0)
		data.encode_s16(index * 2, clampi(sample, -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


func _make_music_stream() -> AudioStreamWAV:
	var rate := 12000
	var duration := 4.0
	var count := int(duration * rate)
	var notes := [110.0, 146.83, 164.81, 146.83, 110.0, 164.81, 196.0, 146.83]
	var data := PackedByteArray()
	data.resize(count * 2)
	for index: int in count:
		var t := float(index) / float(rate)
		var step := int(t * 2.0) % notes.size()
		var frequency: float = notes[step]
		var pulse := maxf(0.0, sin(fmod(t, 0.5) * TAU * 2.0))
		var sample := int((sin(TAU * frequency * t) + sin(TAU * frequency * 2.0 * t) * 0.22) * pulse * 0.025 * 32767.0)
		data.encode_s16(index * 2, clampi(sample, -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	stream.data = data
	return stream


func debug_apply_snapshot(snapshot: Dictionary) -> void:
	_has_welcome = true
	_menu.hide()
	_board.show()
	_toolbar.show()
	_score_label.show()
	_room_label.show()
	_status_label.show()
	_role = str(snapshot.get("role", "left"))
	snapshot = snapshot.duplicate(true)
	snapshot["marker"] = ProtocolType.BUILD
	snapshot["room"] = _room_code
	snapshot["players"] = {"left": true, "right": true}
	for side in ["left", "right"]:
		snapshot.paddles[side].merge({"vy": 0.0, "ack_seq": 0, "sent_msec": 0})
	_last_snapshot_seq = -1
	_handle_packet(JSON.stringify(snapshot))


func _build_menu() -> void:
	# Attract mode: a cosmetic CPU rally plays behind the title like an arcade cabinet demo.
	_attract = AttractCourtType.new()
	_attract.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_attract)
	_menu = VBoxContainer.new()
	_menu.name = "TitleMenu"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.offset_left = 24.0
	_menu.offset_top = 24.0
	_menu.offset_right = -24.0
	_menu.offset_bottom = -16.0
	_menu.add_theme_constant_override("separation", 0)
	_menu.visibility_changed.connect(func() -> void:
		_attract.visible = _menu.visible
		if _menu.visible:
			_play_menu_intro()
	)
	add_child(_menu)
	var top_fill := Control.new()
	top_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu.add_child(top_fill)
	var columns := HBoxContainer.new()
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_theme_constant_override("separation", 72)
	_menu.add_child(columns)
	# Left: neon sign logo lockup over the attract court.
	var brand := VBoxContainer.new()
	_brand = brand
	brand.custom_minimum_size.x = 480.0
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 0)
	columns.add_child(brand)
	_title_main = NeonTextType.new()
	_title_main.add_theme_font_override("font", load(FONT_TITLE))
	_title_main.add_theme_font_size_override("font_size", 52)
	_title_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_main.glow = COLOR_ONLINE
	_title_main.extrude = Vector2(0.0, 9.0)
	_title_main.extrude_color = Color("0f4a45")
	brand.add_child(_title_main)
	_title_sub = NeonTextType.new()
	_title_sub.add_theme_font_override("font", load(FONT_TITLE_TRACKED))
	_title_sub.add_theme_font_size_override("font_size", 34)
	_title_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_sub.glow = COLOR_P2
	_title_sub.core = Color("ffe3f0")
	_title_sub.flicker = true
	brand.add_child(_title_sub)
	brand.add_child(_spacer(20.0))
	var subtitle := _make_label(18, Color("a9b8c8"), FONT_REGULAR)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size.x = 420.0
	_labels[subtitle] = "app.subtitle"
	brand.add_child(subtitle)
	brand.add_child(_spacer(30.0))
	_attract_prompt = _make_label(15, COLOR_WAITING, FONT_CAPTION)
	_attract_prompt.add_theme_color_override("font_shadow_color", Color(COLOR_WAITING, 0.35))
	_attract_prompt.add_theme_constant_override("shadow_offset_y", 0)
	_attract_prompt.add_theme_constant_override("shadow_outline_size", 6)
	_labels[_attract_prompt] = "attract.prompt"
	brand.add_child(_attract_prompt)
	# Right: lobby cabinet — versus slots, LED room code, arcade join button, settings.
	var card := PanelContainer.new()
	_lobby = card
	card.custom_minimum_size.x = 440.0
	var card_style := _box(Color(0.03, 0.07, 0.1, 0.94), Color(COLOR_ONLINE, 0.32), 6, 2)
	card_style.set_content_margin_all(28.0)
	card_style.content_margin_top = 24.0
	card_style.content_margin_bottom = 24.0
	card_style.shadow_color = Color(COLOR_ONLINE, 0.12)
	card_style.shadow_size = 28
	card.add_theme_stylebox_override("panel", card_style)
	card.draw.connect(_draw_cabinet_trim.bind(card))
	columns.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	card.add_child(body)
	body.add_child(_build_versus_row())
	body.add_child(_spacer(18.0))
	var header := HBoxContainer.new()
	body.add_child(header)
	var room_caption := _make_caption(12)
	room_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_captions[room_caption] = "room"
	header.add_child(room_caption)
	var languages := HBoxContainer.new()
	_languages = languages
	languages.add_theme_constant_override("separation", 0)
	header.add_child(languages)
	for locale: String in ["en", "zh-CN"]:
		var button := Button.new()
		button.text = "EN" if locale == "en" else "CN"
		button.name = "LanguageEN" if locale == "en" else "LanguageCN"
		button.toggle_mode = true
		button.button_pressed = I18n.get_locale() == locale
		button.custom_minimum_size = Vector2(46.0, 28.0)
		_style_segment(button, locale == "en")
		button.pressed.connect(func():
			I18n.set_locale(locale)
			for child in languages.get_children():
				child.set_pressed_no_signal(child == button)
		)
		languages.add_child(button)
	body.add_child(_spacer(10.0))
	_room_input = LineEdit.new()
	_room_input.name = "RoomInput"
	_room_input.max_length = 8
	_room_input.custom_minimum_size.y = 66.0
	_room_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_input.add_theme_font_override("font", load(FONT_CODE))
	_room_input.add_theme_font_size_override("font_size", 32)
	_room_input.add_theme_color_override("font_color", Color("b9fff0"))
	_room_input.add_theme_color_override("font_outline_color", Color(COLOR_ONLINE, 0.35))
	_room_input.add_theme_constant_override("outline_size", 6)
	_room_input.add_theme_color_override("font_placeholder_color", Color(COLOR_MUTED, 0.6))
	_room_input.add_theme_color_override("caret_color", COLOR_ONLINE)
	_room_input.add_theme_color_override("selection_color", Color(COLOR_ONLINE, 0.3))
	# LED display well: deep inset with a bright bezel lip on focus.
	var led := _box(Color("02080c"), Color("16303c"), 6, 2)
	led.border_width_top = 3
	_room_input.add_theme_stylebox_override("normal", led)
	var led_focus := _box(Color("031014"), COLOR_ONLINE, 6, 2)
	led_focus.border_width_top = 3
	led_focus.shadow_color = Color(COLOR_ONLINE, 0.25)
	led_focus.shadow_size = 12
	_room_input.add_theme_stylebox_override("focus", led_focus)
	_room_input.draw.connect(_draw_led_scanlines)
	body.add_child(_room_input)
	body.add_child(_spacer(16.0))
	var play := _button("play", _start_game)
	_play_button = play
	_style_primary(play)
	body.add_child(play)
	body.add_child(_spacer(10.0))
	_hint = _make_label(14, COLOR_MUTED, FONT_REGULAR)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.custom_minimum_size = Vector2(384.0, 40.0)
	_hint.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	_labels[_hint] = "controls"
	body.add_child(_hint)
	body.add_child(_spacer(14.0))
	var divider := ColorRect.new()
	divider.color = Color(COLOR_ONLINE, 0.18)
	divider.custom_minimum_size.y = 1.0
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(divider)
	body.add_child(_spacer(14.0))
	var settings_caption := _make_caption(12)
	_captions[settings_caption] = "settings"
	body.add_child(settings_caption)
	body.add_child(_spacer(4.0))
	var mute := CheckButton.new()
	_labels[mute] = "mute"
	mute.custom_minimum_size.y = 38.0
	mute.add_theme_font_size_override("font_size", 16)
	mute.add_theme_font_override("font", load(FONT_REGULAR))
	mute.add_theme_color_override("font_color", COLOR_TEXT)
	mute.add_theme_color_override("font_hover_color", Color.WHITE)
	mute.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	mute.add_theme_color_override("font_focus_color", Color.WHITE)
	mute.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	# Neon pill switch (drawn procedurally) instead of the default theme toggle.
	var switch_on := _switch_icon(true)
	var switch_off := _switch_icon(false)
	for icon_name: String in ["checked", "checked_mirrored"]:
		mute.add_theme_icon_override(icon_name, switch_on)
	for icon_name: String in ["unchecked", "unchecked_mirrored"]:
		mute.add_theme_icon_override(icon_name, switch_off)
	# Zero side padding so the label shares the left edge with the slider labels.
	var flat := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		mute.add_theme_stylebox_override(state, flat)
	mute.add_theme_stylebox_override("focus", _focus_ring(8))
	mute.toggled.connect(func(value: bool): TuningStore.set_value("audio.master.muted", value, false))
	body.add_child(mute)
	_settings_controls["audio.master.muted"] = mute
	mute.set_pressed_no_signal(TuningStore.get_value("audio.master.muted", false))
	for item in [["music", "audio.music.volume_db"], ["effects", "audio.sfx.volume_db"]]:
		var line := HBoxContainer.new()
		line.custom_minimum_size.y = 38.0
		line.add_theme_constant_override("separation", 16)
		var label := _make_label(16, COLOR_TEXT, FONT_REGULAR)
		label.custom_minimum_size.x = 140
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		_labels[label] = item[0]
		line.add_child(label)
		var slider := HSlider.new()
		slider.min_value = -40
		slider.max_value = 0
		slider.value = TuningStore.get_value(item[1], -18)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_slider(slider)
		var setting: String = item[1]
		slider.value_changed.connect(func(value: float): TuningStore.set_value(setting, value, false))
		line.add_child(slider)
		body.add_child(line)
		_settings_controls[setting] = slider
	var bottom_fill := Control.new()
	bottom_fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu.add_child(bottom_fill)
	# Quiet footer utility; the Tweak Controls launcher owns the opposite corner.
	var footer := HBoxContainer.new()
	_menu.add_child(footer)
	var licenses := _button("ui.open_source_licenses", OpenSourceLicenses.open.bind(self))
	licenses.name = "OpenSourceLicensesButton"
	_style_quiet(licenses)
	footer.add_child(licenses)
	_toolbar = HBoxContainer.new()
	_toolbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_toolbar.position = Vector2(24, -58)
	_toolbar.add_theme_constant_override("separation", 12)
	add_child(_toolbar)
	for entry in [["copy", _copy_invite], ["retry", _retry], ["leave", _leave_room]]:
		var action := _button(entry[0], entry[1])
		_style_secondary(action)
		_toolbar.add_child(action)
	_start_blink(_attract_prompt, 1.1)
	call_deferred("_play_menu_intro")


## Versus header: P1 (you) — VS — P2 (open seat), in player colours.
func _build_versus_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for side: int in 2:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(150.0, 52.0)
		var color := COLOR_ONLINE if side == 0 else COLOR_P2
		var slot_style := _box(Color(color, 0.08), Color(color, 0.55), 4, 1)
		slot_style.skew = Vector2(-0.2 if side == 0 else 0.2, 0.0)
		slot_style.border_width_bottom = 3
		slot_style.content_margin_top = 4.0
		slot_style.content_margin_bottom = 4.0
		slot.add_theme_stylebox_override("panel", slot_style)
		var stack := VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", -2)
		slot.add_child(stack)
		var tag := _make_label(20, color, FONT_TITLE)
		tag.text = "P1" if side == 0 else "P2"
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_color_override("font_shadow_color", Color(color, 0.35))
		tag.add_theme_constant_override("shadow_offset_y", 0)
		tag.add_theme_constant_override("shadow_outline_size", 6)
		stack.add_child(tag)
		var who := _make_label(11, Color(COLOR_TEXT, 0.75), FONT_CAPTION)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		if side == 0:
			_captions[who] = "you"
		else:
			who.text = "? ? ?"
			_start_blink(who, 0.9)
		stack.add_child(who)
		row.add_child(slot)
		if side == 0:
			var versus := NeonTextType.new()
			versus.text = "VS"
			versus.add_theme_font_override("font", load(FONT_TITLE))
			versus.add_theme_font_size_override("font_size", 30)
			versus.glow = COLOR_WAITING
			versus.core = Color("fff4d6")
			versus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			versus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(versus)
	return row


func _draw_cabinet_trim(card: Control) -> void:
	var rect := Rect2(Vector2.ZERO, card.size)
	var arm := 20.0
	for corner: Array in [[rect.position, Vector2(1, 1)], [Vector2(rect.end.x, 0.0), Vector2(-1, 1)], [Vector2(0.0, rect.end.y), Vector2(1, -1)], [rect.end, Vector2(-1, -1)]]:
		var p: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		card.draw_line(p, p + Vector2(arm * d.x, 0.0), COLOR_ONLINE, 3.0)
		card.draw_line(p, p + Vector2(0.0, arm * d.y), COLOR_ONLINE, 3.0)
	card.draw_rect(Rect2(Vector2(rect.size.x * 0.5 - 40.0, -2.0), Vector2(80.0, 4.0)), COLOR_P2)


func _draw_led_scanlines() -> void:
	var y := 6.0
	while y < _room_input.size.y - 4.0:
		_room_input.draw_line(Vector2(6.0, y), Vector2(_room_input.size.x - 6.0, y), Color(COLOR_ONLINE, 0.035), 1.0)
		y += 3.0


func _switch_icon(on: bool) -> ImageTexture:
	var width := 46
	var height := 26
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var track := Color(COLOR_ONLINE, 0.9) if on else Color("15293a")
	var rim := Color(COLOR_ONLINE, 1.0) if on else Color("2d4a5c")
	var knob := Color("f2fffb") if on else Color("7f91a3")
	var radius := height * 0.5 - 1.0
	var knob_center := Vector2(width - height * 0.5, height * 0.5) if on else Vector2(height * 0.5, height * 0.5)
	for y: int in height:
		for x: int in width:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, height * 0.5, width - height * 0.5)
			var d := p.distance_to(Vector2(cx, height * 0.5)) - radius
			var color := Color(0.0, 0.0, 0.0, 0.0)
			if d < 0.5:
				color = rim if d > -1.5 else track
				color.a *= clampf(0.5 - d, 0.0, 1.0)
			var kd := p.distance_to(knob_center) - (radius - 3.0)
			if kd < 0.5:
				color = color.blend(Color(knob, clampf(0.5 - kd, 0.0, 1.0)))
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _grabber_icon(hot: bool) -> ImageTexture:
	var extent := 20
	var image := Image.create(extent, extent, false, Image.FORMAT_RGBA8)
	var center := Vector2(extent, extent) * 0.5
	for y: int in extent:
		for x: int in extent:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var diamond := absf(p.x) + absf(p.y)
			var color := Color(COLOR_ONLINE, clampf((10.0 - diamond) / 4.0, 0.0, 1.0) * (0.35 if hot else 0.22))
			if diamond < 6.5:
				color = Color("f2fffb") if diamond < 4.5 else COLOR_ONLINE
				color.a = clampf(6.5 - diamond, 0.0, 1.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _start_blink(control: CanvasItem, period: float) -> void:
	if bool(TuningStore.get_value("ui.reduced_motion", false)):
		return
	var tween := control.create_tween().set_loops()
	tween.tween_property(control, "modulate:a", 0.25, period * 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(control, "modulate:a", 1.0, period * 0.5).set_trans(Tween.TRANS_SINE)


## Title entrance: logo powers on, lobby cabinet slides in, then the join button takes focus.
func _play_menu_intro() -> void:
	if _brand == null or not _menu.visible:
		return
	if is_instance_valid(_play_button):
		_play_button.call_deferred("grab_focus")
	if bool(TuningStore.get_value("ui.reduced_motion", false)):
		return
	_title_main.modulate.a = 0.0
	_title_sub.modulate.a = 0.0
	_lobby.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	_title_main.pivot_offset = Vector2(0.0, _title_main.size.y * 0.5)
	_title_main.scale = Vector2(1.12, 1.12)
	tween.tween_property(_title_main, "modulate:a", 1.0, 0.12).set_delay(0.1)
	tween.tween_property(_title_main, "modulate:a", 0.35, 0.05).set_delay(0.24)
	tween.tween_property(_title_main, "modulate:a", 1.0, 0.08).set_delay(0.3)
	tween.tween_property(_title_main, "scale", Vector2.ONE, 0.55).set_delay(0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_title_sub, "modulate:a", 1.0, 0.3).set_delay(0.45)
	tween.tween_property(_lobby, "modulate:a", 1.0, 0.35).set_delay(0.3)
	_lobby.pivot_offset = _lobby.size * 0.5
	_lobby.scale = Vector2(0.94, 0.94)
	tween.tween_property(_lobby, "scale", Vector2.ONE, 0.5).set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Versus shutter: two blast doors part from a glowing seam when a match screen opens/closes.
func _play_shutter() -> void:
	if _shutter == null or bool(TuningStore.get_value("ui.reduced_motion", false)):
		return
	_shutter_progress = 0.0
	_shutter.visible = true
	_shutter.queue_redraw()
	var tween := create_tween()
	tween.tween_interval(0.12)
	tween.tween_method(_set_shutter, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: _shutter.visible = false)


func _set_shutter(value: float) -> void:
	_shutter_progress = value
	_shutter.queue_redraw()


func _draw_shutter() -> void:
	var half := size.y * 0.5 * (1.0 - _shutter_progress)
	var door := Color("03090d")
	_shutter.draw_rect(Rect2(0.0, 0.0, size.x, half), door)
	_shutter.draw_rect(Rect2(0.0, size.y - half, size.x, half), door)
	for edge: float in [half, size.y - half]:
		_shutter.draw_rect(Rect2(0.0, edge - 3.0, size.x, 6.0), Color(COLOR_ONLINE, 0.25 * (1.0 - _shutter_progress)))
		_shutter.draw_line(Vector2(0.0, edge), Vector2(size.x, edge), Color(COLOR_ONLINE, 1.0 - _shutter_progress * 0.6), 2.0)


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _make_caption(font_size: int) -> Label:
	var caption := _make_label(font_size, COLOR_MUTED, FONT_CAPTION)
	caption.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return caption


func _box(background: Color, border: Color, radius: int = 10, border_width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	box.anti_aliasing = true
	return box


func _focus_ring(radius: int = 12, color: Color = COLOR_ONLINE) -> StyleBoxFlat:
	var ring := _box(Color.TRANSPARENT, color, radius + 3, 2)
	ring.set_expand_margin_all(3.0)
	return ring


func _style_primary(button: Button) -> void:
	# Physical arcade button: lit face, thick darker bevel below, glow; press sinks it.
	button.custom_minimum_size.y = 58.0
	button.add_theme_font_override("font", load(FONT_CAPTION))
	button.add_theme_font_size_override("font_size", 17)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, COLOR_INK)
	var normal := _box(COLOR_ONLINE, Color("1f8f77"), 10, 0)
	normal.border_width_bottom = 6
	normal.shadow_color = Color(COLOR_ONLINE, 0.3)
	normal.shadow_size = 18
	normal.shadow_offset = Vector2(0.0, 2.0)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("86f2da")
	hover.shadow_color = Color(COLOR_ONLINE, 0.5)
	hover.shadow_size = 24
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("46cdb0")
	pressed.border_width_bottom = 1
	pressed.content_margin_top = 13.0
	pressed.content_margin_bottom = 3.0
	pressed.expand_margin_top = -5.0
	button.add_theme_stylebox_override("pressed", pressed)
	var focus := _focus_ring(12, Color.WHITE)
	focus.expand_margin_bottom = 3.0
	button.add_theme_stylebox_override("focus", focus)


func _style_secondary(button: Button) -> void:
	# Skewed neon-outline chips for in-match utilities.
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_font_override("font", load(FONT_CAPTION))
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("bfe9df"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_INK)
	for state: String in ["normal", "hover", "pressed"]:
		var chip := _box(Color(0.02, 0.07, 0.09, 0.9) if state == "normal" else (Color(COLOR_ONLINE, 0.14) if state == "hover" else COLOR_ONLINE), Color(COLOR_ONLINE, 0.4 if state == "normal" else 0.95), 3, 1)
		chip.skew = Vector2(0.22, 0.0)
		chip.content_margin_left = 20.0
		chip.content_margin_right = 20.0
		if state == "hover":
			chip.shadow_color = Color(COLOR_ONLINE, 0.25)
			chip.shadow_size = 10
		button.add_theme_stylebox_override(state, chip)
	var focus := _focus_ring(4)
	focus.skew = Vector2(0.22, 0.0)
	button.add_theme_stylebox_override("focus", focus)


func _style_quiet(button: Button) -> void:
	button.custom_minimum_size = Vector2(0.0, 32.0)
	button.add_theme_font_override("font", load(FONT_REGULAR))
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color(COLOR_MUTED, 0.85))
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT)
	var flat := _box(Color.TRANSPARENT, Color.TRANSPARENT, 8, 0)
	flat.content_margin_left = 8.0
	flat.content_margin_right = 8.0
	button.add_theme_stylebox_override("normal", flat)
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", _focus_ring(8))


func _style_segment(button: Button, first: bool) -> void:
	button.add_theme_font_override("font", load(FONT_CAPTION))
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_MUTED)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_INK)
	button.add_theme_color_override("font_hover_pressed_color", COLOR_INK)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var active := state.contains("pressed")
		var box := _box(COLOR_ONLINE if active else (Color("12263a") if state == "hover" else Color.TRANSPARENT), COLOR_ONLINE if active else COLOR_LINE, 8)
		box.content_margin_left = 8.0
		box.content_margin_right = 8.0
		box.content_margin_top = 4.0
		box.content_margin_bottom = 4.0
		if first:
			box.corner_radius_top_right = 0
			box.corner_radius_bottom_right = 0
		else:
			box.corner_radius_top_left = 0
			box.corner_radius_bottom_left = 0
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", _focus_ring(8))


func _style_slider(slider: HSlider) -> void:
	var track := _box(Color("15293a"), Color("15293a"), 3, 0)
	track.content_margin_top = 3.0
	track.content_margin_bottom = 3.0
	slider.add_theme_stylebox_override("slider", track)
	var fill := _box(Color(COLOR_ONLINE, 0.85), Color(COLOR_ONLINE, 0.85), 3, 0)
	fill.content_margin_top = 3.0
	fill.content_margin_bottom = 3.0
	slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_hot := fill.duplicate() as StyleBoxFlat
	fill_hot.bg_color = COLOR_ONLINE
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hot)
	slider.add_theme_stylebox_override("focus", _focus_ring(6))
	slider.add_theme_icon_override("grabber", _grabber_icon(false))
	slider.add_theme_icon_override("grabber_highlight", _grabber_icon(true))

func _button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 40)
	button.pressed.connect(action)
	_labels[button] = key
	AudioDirector.register_button(button)
	return button

func _refresh_language() -> void:
	_languages.get_child(0).set_pressed_no_signal(I18n.get_locale() == "en")
	_languages.get_child(1).set_pressed_no_signal(I18n.get_locale() == "zh-CN")
	for control in _labels:
		control.text = I18n.t(_labels[control])
	for caption in _captions:
		caption.text = I18n.t(_captions[caption]).to_upper()
	# The title is typeset as a two-line lockup; titles without a slash stay on one line.
	var title_parts := I18n.t("app.title").split("/", false)
	_title_main.text = title_parts[0].strip_edges()
	_title_sub.text = title_parts[1].strip_edges() if title_parts.size() > 1 else ""
	_title_sub.visible = not _title_sub.text.is_empty()
	_room_input.placeholder_text = I18n.t("room")
	if _play_button != null:
		_play_button.text = I18n.t("play").to_upper()
	for toolbar_button: Node in _toolbar.get_children():
		(toolbar_button as Button).text = (toolbar_button as Button).text.to_upper()
	_set_status(_status_key, _status_color)

func _show_menu() -> void:
	_board.hide()
	_menu.show()
	_toolbar.hide()
	_status_label.hide()
	_score_label.hide()
	_room_label.hide()

func _start_game() -> void:
	var room := _room_input.text.to_upper()
	if not ProtocolType.valid_room(room):
		_hint.text = I18n.t("invalid.room")
		return
	_room_code = room
	_resume_token = _load_resume_token(room)
	if OS.has_feature("web"):
		_write_room_url(room)
	_playing = true
	_menu.hide()
	_board.show()
	_toolbar.show()
	_status_label.show()
	_score_label.show()
	_room_label.show()
	AudioDirector.unlock_audio()
	_start_music()
	_play_shutter()
	_discover_endpoint()

func _discover_endpoint() -> void:
	_connection.start(ProtocolType.BUILD, "PONG_WS_URL", _websocket_url)


func _retry() -> void:
	_has_welcome = false
	_playing = true
	_board.stop_local()
	_discover_endpoint()


func _leave_room() -> void:
	_board.stop_local()
	_send_input(0.0)
	_playing = false
	_connection.stop()
	_has_welcome = false
	_pointer_active = false
	_pointer_axis = 0.0
	AudioDirector.stop_music()
	_music_started = false
	_play_shutter()
	_show_menu()

func _copy_invite() -> void:
	if OS.has_feature("web"):
		var script := "(() => { const u = new URL(location.href); const room = u.searchParams.get('room'); u.search = ''; u.hash = ''; u.searchParams.set('room', room); return u.href; })()"
		DisplayServer.clipboard_set(str(JavaScriptBridge.eval(script, true)))
	else:
		DisplayServer.clipboard_set(_room_code)

func _apply_presentation() -> void:
	_board.smoothing = float(TuningStore.get_value("presentation.smoothing", 24.0))
	_board.reduced_motion = bool(TuningStore.get_value("ui.reduced_motion", false))


func _sync_settings_controls() -> void:
	for id: String in _settings_controls:
		var control: Control = _settings_controls[id]
		if control is CheckButton:
			control.set_pressed_no_signal(TuningStore.get_value(id))
		else:
			control.set_value_no_signal(TuningStore.get_value(id))
