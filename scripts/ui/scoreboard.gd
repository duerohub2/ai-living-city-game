extends Control
## Arcade versus scoreboard drawn over the (transparent) score Label it belongs to: two
## LED windows in a bezel, P1/P2 tags in player colours, and a punch when a side scores.
## The Label keeps the authoritative "L   R" text; this control only presents it.

const P1 := Color("59e1c2")
const P2 := Color("ff5fa2")
const BEZEL := Color("0b1722")

var local_role := "spectator"
var you_text := "YOU":
	set(value):
		you_text = value.to_upper()

var _scores := ["0", "0"]
var _punch := [0.0, 0.0]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var owner_label := get_parent() as Label
	if owner_label == null or not is_visible_in_tree():
		return
	var parts := owner_label.text.split(" ", false)
	var next := [parts[0] if parts.size() > 0 else "0", parts[1] if parts.size() > 1 else "0"]
	var reduced := bool(TuningStore.get_value("ui.reduced_motion", false))
	for side: int in 2:
		if next[side] != _scores[side] and not reduced and _scores[side] != "":
			_punch[side] = 1.0
		_punch[side] = maxf(0.0, float(_punch[side]) - delta * 3.5)
	_scores = next
	queue_redraw()


func _draw() -> void:
	var owner_label := get_parent() as Label
	if owner_label == null:
		return
	var font := owner_label.get_theme_font("font")
	var font_size := owner_label.get_theme_font_size("font_size") + 6
	var caption_font: Font = load("res://assets/template/fonts/display/pong_caption.tres")
	var center := size * 0.5
	var window := Vector2(112.0, size.y - 18.0)
	var gap := 44.0
	var bezel := Rect2(center - Vector2(window.x + gap * 0.5 + 10.0, window.y * 0.5 + 6.0), Vector2(window.x * 2.0 + gap + 20.0, window.y + 12.0))
	draw_rect(bezel.grow(3.0), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(bezel, BEZEL)
	draw_rect(bezel, Color("1c3444"), false, 2.0)
	draw_line(bezel.position + Vector2(6.0, 1.5), Vector2(bezel.end.x - 6.0, bezel.position.y + 1.5), Color(1.0, 1.0, 1.0, 0.08), 1.0)
	# Centre divider: stacked dots like a pixel colon.
	for dot: int in 2:
		draw_rect(Rect2(center + Vector2(-3.0, -12.0 + dot * 18.0), Vector2(6.0, 6.0)), Color(0.9, 0.95, 1.0, 0.55))
	for side: int in 2:
		var color := P1 if side == 0 else P2
		var direction := -1.0 if side == 0 else 1.0
		var window_rect := Rect2(Vector2(center.x + direction * (gap * 0.5 + window.x * 0.5) - window.x * 0.5, center.y - window.y * 0.5), window)
		draw_rect(window_rect, Color(0.01, 0.03, 0.05, 1.0))
		draw_rect(window_rect, Color(color, 0.35), false, 1.0)
		var baseline := center.y - font.get_height(font_size) * 0.5 + font.get_ascent(font_size)
		var digits: String = _scores[side]
		var width := font.get_string_size(digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var kick := float(_punch[side])
		var scale_factor := 1.0 + 0.28 * kick * kick
		var pivot := window_rect.get_center()
		draw_set_transform(pivot, 0.0, Vector2.ONE * scale_factor)
		var origin := Vector2(-width * 0.5, baseline - pivot.y)
		for pass_data: Array in [[16, 0.07], [9, 0.14], [4, 0.45]]:
			draw_string_outline(font, origin, digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, pass_data[0], Color(color, float(pass_data[1]) * (1.0 + kick)))
		draw_string(font, origin, digits, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color.lerp(Color.WHITE, 0.7 + 0.3 * kick))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Player tag outside the bezel; the local seat is marked "YOU".
		var tag := "P1" if side == 0 else "P2"
		var tag_size := 15
		var tag_width := caption_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size).x
		var tag_x := bezel.position.x - 14.0 - tag_width if side == 0 else bezel.end.x + 14.0
		draw_string(caption_font, Vector2(tag_x, center.y - 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_size, color)
		if local_role == ("left" if side == 0 else "right"):
			var you_width := caption_font.get_string_size(you_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var you_x := bezel.position.x - 14.0 - you_width if side == 0 else bezel.end.x + 14.0
			draw_string(caption_font, Vector2(you_x, center.y + 16.0), you_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.97, 1.0, 0.8))
