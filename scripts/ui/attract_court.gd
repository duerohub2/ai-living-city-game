extends Control
## Attract-mode backdrop for the title/lobby: a purely cosmetic CPU-vs-CPU rally on a
## neon CRT court. It never touches the network match or the authoritative simulation.

const P1 := Color("59e1c2")
const P2 := Color("ff5fa2")
const LINE := Color("1c3444")

var _ball := Vector2(0.5, 0.5)
var _velocity := Vector2(0.34, 0.21)
var _left := 0.5
var _right := 0.5
var _trail: Array[Vector2] = []
var _flash := 0.0
var _flash_side := 0
var _glow: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 1.0, 1.0, 0.3), Color(1.0, 1.0, 1.0, 0.0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if bool(TuningStore.get_value("ui.reduced_motion", false)):
		queue_redraw()
		return
	_ball += _velocity * delta
	if _ball.y < 0.06 or _ball.y > 0.94:
		_velocity.y = -_velocity.y
		_ball.y = clampf(_ball.y, 0.06, 0.94)
	if _ball.x < 0.07 or _ball.x > 0.93:
		_velocity.x = -_velocity.x
		_velocity.y = clampf(_velocity.y + randf_range(-0.08, 0.08), -0.32, 0.32)
		_ball.x = clampf(_ball.x, 0.07, 0.93)
		_flash = 1.0
		_flash_side = -1 if _ball.x < 0.5 else 1
	# Lazy trackers: each paddle only follows the ball on its own half.
	_left = lerpf(_left, _ball.y if _ball.x < 0.55 else 0.5, 1.0 - exp(-delta * 3.2))
	_right = lerpf(_right, _ball.y if _ball.x > 0.45 else 0.5, 1.0 - exp(-delta * 3.2))
	_trail.push_front(_ball)
	if _trail.size() > 14:
		_trail.pop_back()
	_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var court := Rect2(Vector2(24.0, 24.0), size - Vector2(48.0, 48.0))
	draw_rect(court, Color(LINE, 0.55), false, 2.0)
	var dash := 18.0
	var y := court.position.y + 12.0
	while y < court.end.y - 12.0:
		draw_rect(Rect2(size.x * 0.5 - 1.5, y, 3.0, dash), Color(LINE, 0.9))
		y += dash + 14.0
	draw_arc(size * 0.5, 64.0, 0.0, TAU, 64, Color(LINE, 0.7), 2.0, true)
	var paddle := Vector2(14.0, court.size.y * 0.2)
	for side: Array in [[court.position.x + 28.0, _left, P1, -1], [court.end.x - 28.0, _right, P2, 1]]:
		var center := Vector2(float(side[0]), court.position.y + court.size.y * float(side[1]))
		var color: Color = side[2]
		var hit := _flash if _flash_side == int(side[3]) else 0.0
		draw_texture_rect(_glow, Rect2(center - Vector2(60.0, paddle.y * 0.9), Vector2(120.0, paddle.y * 1.8)), false, Color(color, 0.16 + hit * 0.2))
		draw_rect(Rect2(center - paddle * 0.5, paddle), Color(color.lerp(Color.WHITE, 0.25 + hit * 0.4), 0.55))
	for index: int in _trail.size():
		var point := court.position + court.size * _trail[index]
		draw_circle(point, 8.0 * (1.0 - float(index) / 14.0), Color(P1, 0.14 * (1.0 - float(index) / 14.0)))
	var ball := court.position + court.size * _ball
	draw_texture_rect(_glow, Rect2(ball - Vector2(36.0, 36.0), Vector2(72.0, 72.0)), false, Color(P1, 0.35))
	draw_circle(ball, 8.0, Color(0.85, 1.0, 0.97, 0.7))
