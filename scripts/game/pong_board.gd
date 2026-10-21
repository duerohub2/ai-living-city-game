class_name PongBoard
extends Control

const LocalPaddle := preload("res://scripts/game/local_paddle.gd")

const FIELD := Color("0a1621")
const BORDER := Color("213849")
const CENTER := Color("274355")
const INK := Color("f2f7ff")
const ACCENT := Color("59e1c2")
const P1_COLOR := Color("59e1c2")
const P2_COLOR := Color("ff5fa2")

var local_paddle := LocalPaddle.new()
var local_role := "spectator"

var _initialized := false
var _target_ball := Vector2(0.5, 0.5)
var _visual_ball := Vector2(0.5, 0.5)
var _target_left := 0.5
var _visual_left := 0.5
var _target_right := 0.5
var _visual_right := 0.5
var _phase := "waiting"
var _event_kind := ""
var _event_flash := 0.0
var _last_event_seq := -1
var smoothing := 24.0
var reduced_motion := false
var _trail: Array[Vector2] = []
var _glow: GradientTexture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	resized.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	var weight := 1.0 - exp(-delta * smoothing)
	_visual_ball = _visual_ball.lerp(_target_ball, weight)
	_visual_left = lerpf(_visual_left, _target_left, weight)
	_visual_right = lerpf(_visual_right, _target_right, weight)
	if local_role == "left" and local_paddle.initialized:
		_visual_left = local_paddle.advance(delta)
	elif local_role == "right" and local_paddle.initialized:
		_visual_right = local_paddle.advance(delta)
	_event_flash = maxf(0.0, _event_flash - delta * 4.0)
	queue_redraw()


func configure_local(role: String, movement: Dictionary) -> void:
	local_role = role
	local_paddle.configure(movement)
	_initialized = false


func stop_local() -> void:
	local_paddle.reset()
	local_role = "spectator"


func set_local_input(axis: float, next_seq: int) -> void:
	local_paddle.set_input(axis, next_seq)


func apply_snapshot(snapshot: Dictionary) -> void:
	var ball: Dictionary = snapshot.get("ball", {})
	var paddles: Dictionary = snapshot.get("paddles", {})
	_target_ball = Vector2(float(ball.get("x", 0.5)), float(ball.get("y", 0.5)))
	_target_left = float((paddles.get("left", {}) as Dictionary).get("y", 0.5))
	_target_right = float((paddles.get("right", {}) as Dictionary).get("y", 0.5))
	_phase = str(snapshot.get("phase", "waiting"))
	if local_role in ["left", "right"]:
		local_paddle.accept(paddles[local_role], _phase == "live", int(snapshot.seq), Time.get_ticks_msec())
	var event: Dictionary = snapshot.get("event", {})
	var new_event := str(event.get("kind", ""))
	if not new_event.is_empty() and int(event.get("seq", -1)) > _last_event_seq:
		_event_flash = 1.0
	_event_kind = new_event
	_last_event_seq = int(event.get("seq", -1))
	if not _initialized:
		_visual_ball = _target_ball
		_visual_left = _target_left
		_visual_right = _target_right
		_initialized = true
	queue_redraw()


func get_debug_state() -> Dictionary:
	return {
		"ball": _target_ball,
		"left": _target_left,
		"right": _target_right,
		"phase": _phase,
		"visual_left": _visual_left,
		"visual_right": _visual_right,
		"anticipating": local_paddle.active,
	}


func _draw() -> void:
	# Neon CRT court. Geometry (paddle size/position, ball radius) is unchanged; only the
	# material is: player-coloured glowing paddles, a phosphor ball trail and lit court lines.
	var field := Rect2(Vector2.ZERO, size)
	draw_rect(field, FIELD, true)
	if _glow == null:
		_glow = _make_glow()
	draw_texture_rect(_glow, Rect2(Vector2(size.x * 0.1, -size.y * 0.2), Vector2(size.x * 0.8, size.y * 1.4)), false, Color(0.2, 0.55, 0.6, 0.07))
	for inset: int in 3:
		draw_rect(field.grow(float(inset) * 2.0), Color(ACCENT, 0.09 - inset * 0.025), false, 2.0)
	draw_rect(field, BORDER.lerp(ACCENT, 0.25), false, 2.0)
	draw_rect(field.grow(-7.0), Color(BORDER, 0.5), false, 1.0)
	var dash_height := maxf(8.0, size.y * 0.027)
	var gap := dash_height * 0.72
	var y := gap
	while y < size.y - gap:
		draw_rect(Rect2(Vector2(size.x * 0.5 - 3.0, y - 1.0), Vector2(6.0, dash_height + 2.0)), Color(ACCENT, 0.05), true)
		draw_rect(Rect2(Vector2(size.x * 0.5 - 1.0, y), Vector2(2.0, dash_height)), CENTER.lerp(ACCENT, 0.2), true)
		y += dash_height + gap
	draw_arc(size * 0.5, size.y * 0.13, 0.0, TAU, 72, Color(CENTER, 0.8), 2.0, true)
	var paddle_size := Vector2(size.x * 0.024, size.y * 0.22)
	var left_center := Vector2(size.x * 0.05, size.y * _visual_left)
	var right_center := Vector2(size.x * 0.95, size.y * _visual_right)
	var flash := 0.0 if reduced_motion else _event_flash
	for paddle: Array in [[left_center, P1_COLOR], [right_center, P2_COLOR]]:
		var center: Vector2 = paddle[0]
		var color: Color = paddle[1]
		var hit := flash if _event_kind == "paddle" else 0.0
		draw_texture_rect(_glow, Rect2(center - Vector2(paddle_size.x * 3.5, paddle_size.y * 0.85), Vector2(paddle_size.x * 7.0, paddle_size.y * 1.7)), false, Color(color, 0.22 + hit * 0.15))
		var body := Rect2(center - paddle_size * 0.5, paddle_size)
		draw_rect(body.grow(2.0), Color(color, 0.35), true)
		draw_rect(body, color.lerp(INK, 0.35 + hit * 0.3), true)
		draw_rect(Rect2(body.position + Vector2(body.size.x * 0.3, 4.0), Vector2(body.size.x * 0.4, body.size.y - 8.0)), Color(INK, 0.85), true)
	var ball_radius := size.y * 0.014
	var ball_color := ACCENT.lerp(INK, 0.45 + flash * 0.25)
	var ball_position := Vector2(size.x * _visual_ball.x, size.y * _visual_ball.y)
	if not reduced_motion and _phase == "live":
		_trail.push_front(ball_position)
		if _trail.size() > 10:
			_trail.pop_back()
		for index: int in range(1, _trail.size()):
			var fade := 1.0 - float(index) / float(_trail.size())
			draw_circle(_trail[index], ball_radius * (0.4 + 0.6 * fade), Color(ACCENT, 0.18 * fade))
	else:
		_trail.clear()
	draw_texture_rect(_glow, Rect2(ball_position - Vector2.ONE * ball_radius * 5.0, Vector2.ONE * ball_radius * 10.0), false, Color(ACCENT, 0.4 + flash * 0.3))
	draw_circle(ball_position, ball_radius, ball_color)
	if _phase != "live":
		draw_rect(field, Color(0.02, 0.04, 0.06, 0.16), true)


func _make_glow() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.3), Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
