extends Label
## Neon sign lettering: an optional retro extrude, stacked soft outline passes for bloom,
## then a bright core. Text/size still come from the Label, so localisation and layout
## keep working; the built-in glyph draw is made transparent and redrawn here.

var glow := Color("59e1c2")
var core := Color("f2f7ff")
var extrude := Vector2.ZERO
var extrude_color := Color(0.0, 0.0, 0.0, 0.0)
var glow_strength := 1.0
var flicker := false

var _time := 0.0
var _flicker_level := 1.0


func _ready() -> void:
	add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 0.0))
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.0))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var reduced := bool(TuningStore.get_value("ui.reduced_motion", false))
	if flicker and not reduced:
		# Mostly steady tube with brief irregular dips, like an old sign.
		var noise := sin(_time * 23.0) * sin(_time * 3.1 + 1.7)
		_flicker_level = 0.55 if noise > 0.93 else (0.85 if noise > 0.86 else 1.0)
	else:
		_flicker_level = 1.0
	queue_redraw()


func _draw() -> void:
	if text.is_empty():
		return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var line_height := font.get_height(font_size)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := 0.0
	if horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		x = (size.x - width) * 0.5
	elif horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		x = size.x - width
	var y := (size.y - line_height) * 0.5 + font.get_ascent(font_size)
	var origin := Vector2(x, y)
	var level := _flicker_level
	if extrude != Vector2.ZERO:
		draw_string(font, origin + extrude, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, extrude_color)
	for pass_data: Array in [[int(font_size * 0.34), 0.05], [int(font_size * 0.2), 0.08], [int(font_size * 0.1), 0.16]]:
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, pass_data[0]), Color(glow, pass_data[1] * glow_strength * level))
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, int(font_size * 0.035)), Color(glow.lightened(0.25), 0.9 * level))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(core.lerp(glow, 1.0 - level), 1.0))
