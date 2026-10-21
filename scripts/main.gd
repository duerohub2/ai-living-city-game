extends Control

const FONT_BODY := "res://assets/template/fonts/ui_regular.tres"
const FONT_MEDIUM := "res://assets/template/fonts/ui_medium.tres"
const FONT_BOLD := "res://assets/template/fonts/ui_bold.tres"
const FONT_TITLE := "res://assets/template/fonts/display/pong_title.tres"
const CITY_ATLAS := preload("res://assets/generated/city_atlas.png")
const CHARACTER_SPRITE := preload("res://assets/generated/character_sprite.png")
const BUILDING_SET := preload("res://assets/generated/building_set.png")
const SAVE_PATH := "user://livingcity_state.json"

const BG := Color("071522")
const SURFACE := Color("102433")
const SURFACE_2 := Color("162f40")
const LINE := Color("28495a")
const TEXT := Color("f6f2e8")
const MUTED := Color("9ab1b8")
const TEAL := Color("51d3bf")
const GOLD := Color("f4bb68")
const CORAL := Color("f47b74")
const BLUE := Color("76a8ff")

var state: Dictionary = {
	"wallet": 480,
	"reputation": 12,
	"inventory": {"Roti artisan": 2, "Kartu transit": 1},
	"relationships": {"Mira Santoso": 46, "Raka Wijaya": 31, "Naya Chen": 58, "Bimo Ardi": 24},
	"activity": [],
	"ledger": [],
	"last_seen": 0,
	"simulation_hours": 8,
	"needs": {"social": 62, "rest": 78, "income": 44, "recreation": 56, "work": 68}
}

var districts: Array[String] = ["Town Square", "Residential", "Commercial", "Industrial", "Civic", "Park District"]
var district_info: Dictionary = {
	"Town Square": {"tag": "MEETING HUB", "description": "Air mancur kota, event mingguan, dan tempat penghuni bertukar kabar.", "accent": TEAL, "action": "Berinteraksi di plaza"},
	"Residential": {"tag": "HOME LIFE", "description": "Blok rumah tenang tempat jadwal istirahat dan memori sosial bermula.", "accent": GOLD, "action": "Kunjungi tetangga"},
	"Commercial": {"tag": "MARKET", "description": "Toko, kedai, dan job board. Tempat upah bertemu kebutuhan harian.", "accent": CORAL, "action": "Ambil shift toko"},
	"Industrial": {"tag": "PRODUCTION", "description": "Workshop dan gudang yang menjaga stok kota tetap bergerak.", "accent": BLUE, "action": "Kelola produksi"},
	"Civic": {"tag": "GOVERNANCE", "description": "Balai kota, pengumuman publik, dan audit kebijakan manusia.", "accent": Color("c49bff"), "action": "Baca pengumuman"},
	"Park District": {"tag": "RECREATION", "description": "Ruang hijau untuk memulihkan kebutuhan rekreasi dan membangun relasi.", "accent": Color("83d58f"), "action": "Ambil waktu istirahat"}
}
var npc_data: Array[Dictionary] = [
	{"name": "Mira Santoso", "role": "Pemilik kios bunga", "archetype": "Optimis · connector", "memory": "Mira mengingat Anda membantu membawa peti bunga saat festival terakhir.", "need": "social", "color": Color("f29a9a")},
	{"name": "Raka Wijaya", "role": "Teknisi workshop", "archetype": "Pragmatis · builder", "memory": "Raka sedang menguji komponen baru dan menunggu harga logam turun.", "need": "income", "color": Color("82b7ef")},
	{"name": "Naya Chen", "role": "Kurator taman", "archetype": "Tenang · caretaker", "memory": "Naya menandai taman sebagai ruang aman setelah melihat Anda datang untuk istirahat.", "need": "recreation", "color": Color("8dd6a0")},
	{"name": "Bimo Ardi", "role": "Kurir distrik", "archetype": "Waspada · explorer", "memory": "Bimo mendengar rumor pembukaan jalur baru ke Civic District.", "need": "work", "color": Color("e8bd72")}
]

var _selected_district := "Town Square"
var _selected_npc := "Mira Santoso"
var _reduced_motion := false
var _map_stage: Control
var _selected_ring: Panel
var _player_marker: TextureRect
var _details_title: Label
var _details_tag: Label
var _details_description: Label
var _action_button: Button
var _secondary_button: Button
var _wallet_label: Label
var _reputation_label: Label
var _sim_label: Label
var _inventory_label: Label
var _relationship_label: Label
var _memory_label: Label
var _notification_label: Label
var _feed_box: VBoxContainer
var _npc_box: VBoxContainer
var _district_buttons: Dictionary = {}
var _feed_scroll: ScrollContainer
var _offline_banner: PanelContainer
var _offline_text: Label
var _body: Control
var _map_panel: PanelContainer
var _sidebar_panel: PanelContainer
var _last_layout_size := Vector2.ZERO

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_state()
	_apply_offline_catchup()
	_build_interface()
	_select_district(_selected_district)
	_select_npc(_selected_npc)
	_update_all_ui()
	_save_state()

func _process(_delta: float) -> void:
	if _last_layout_size != get_viewport_rect().size:
		_last_layout_size = get_viewport_rect().size
		_layout_body()
	if not _reduced_motion and is_instance_valid(_player_marker):
		_player_marker.rotation = sin(Time.get_ticks_msec() / 600.0) * 0.015

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		state["last_seen"] = int(Time.get_unix_time_from_system())
		_save_state()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_apply_offline_catchup()
		_update_all_ui()

func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var top_bar := PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 18.0
	top_bar.offset_top = 16.0
	top_bar.offset_right = -18.0
	top_bar.offset_bottom = 82.0
	top_bar.add_theme_stylebox_override("panel", _panel_style(Color("0d202e"), LINE, 14, 1))
	add_child(top_bar)
	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 18)
	top_margin.add_theme_constant_override("margin_right", 18)
	top_margin.add_theme_constant_override("margin_top", 10)
	top_margin.add_theme_constant_override("margin_bottom", 10)
	top_bar.add_child(top_margin)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	top_margin.add_child(top_row)
	var brand := VBoxContainer.new()
	brand.custom_minimum_size = Vector2(250, 0)
	top_row.add_child(brand)
	var brand_title := _label("AI LIVING CITY", 21, TEXT, FONT_TITLE)
	brand_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	brand.add_child(brand_title)
	brand.add_child(_label("KOTA YANG MENGINGAT TINDAKANMU", 9, TEAL, FONT_BOLD))
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_spacer)
	var sim_col := VBoxContainer.new()
	sim_col.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(sim_col)
	_sim_label = _label("SIMULASI LOKAL", 10, GOLD, FONT_BOLD)
	_sim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sim_col.add_child(_sim_label)
	var status := _label("●  siap menjelajah · server Render dapat ditambahkan", 11, MUTED, FONT_BODY)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sim_col.add_child(status)
	_wallet_label = _label("CR 480", 19, GOLD, FONT_BOLD)
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(_wallet_label)

	_body = Control.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.offset_left = 18.0
	_body.offset_top = 96.0
	_body.offset_right = -18.0
	_body.offset_bottom = -18.0
	add_child(_body)
	_build_map(_body)
	_build_sidebar(_body)
	_layout_body()

	_offline_banner = PanelContainer.new()
	_offline_banner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_offline_banner.offset_left = -360.0
	_offline_banner.offset_top = 94.0
	_offline_banner.offset_right = -18.0
	_offline_banner.offset_bottom = 136.0
	_offline_banner.add_theme_stylebox_override("panel", _panel_style(Color("26351e"), Color("7ea35c"), 10, 1))
	_offline_banner.visible = false
	add_child(_offline_banner)
	var offline_margin := MarginContainer.new()
	offline_margin.add_theme_constant_override("margin_left", 12)
	offline_margin.add_theme_constant_override("margin_right", 12)
	offline_margin.add_theme_constant_override("margin_top", 8)
	offline_margin.add_theme_constant_override("margin_bottom", 8)
	_offline_banner.add_child(offline_margin)
	_offline_text = _label("", 11, Color("d3edb8"), FONT_MEDIUM)
	offline_margin.add_child(_offline_text)

func _build_map(body: Control) -> void:
	_map_panel = PanelContainer.new()
	var map_panel := _map_panel
	map_panel.name = "CityMap"
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 1.65
	map_panel.add_theme_stylebox_override("panel", _panel_style(Color("0e1c27"), LINE, 16, 1))
	body.add_child(map_panel)
	var map_margin := MarginContainer.new()
	map_margin.add_theme_constant_override("margin_left", 10)
	map_margin.add_theme_constant_override("margin_right", 10)
	map_margin.add_theme_constant_override("margin_top", 10)
	map_margin.add_theme_constant_override("margin_bottom", 10)
	map_panel.add_child(map_margin)
	_map_stage = Control.new()
	_map_stage.clip_contents = true
	map_margin.add_child(_map_stage)
	var map_image := TextureRect.new()
	map_image.texture = CITY_ATLAS
	map_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_stage.add_child(map_image)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.08, 0.12, 0.20)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_stage.add_child(shade)
	var map_caption := _label("KOTA BERSAMA  /  PETA LIVE", 10, TEXT, FONT_BOLD)
	map_caption.position = Vector2(14, 12)
	map_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_map_stage.add_child(map_caption)
	var map_hint := _label("Pilih distrik untuk mengubah state kota", 10, Color("d8e5e5"), FONT_BODY)
	map_hint.position = Vector2(14, 31)
	_map_stage.add_child(map_hint)
	_player_marker = TextureRect.new()
	_player_marker.texture = CHARACTER_SPRITE
	_player_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_marker.anchor_left = 0.50
	_player_marker.anchor_top = 0.53
	_player_marker.anchor_right = 0.50
	_player_marker.anchor_bottom = 0.53
	_player_marker.offset_left = -48
	_player_marker.offset_top = -75
	_player_marker.offset_right = 48
	_player_marker.offset_bottom = 75
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.z_index = 3
	_map_stage.add_child(_player_marker)
	_selected_ring = Panel.new()
	_selected_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selected_ring.z_index = 2
	_selected_ring.add_theme_stylebox_override("panel", _ring_style())
	_map_stage.add_child(_selected_ring)
	for district in districts:
		_add_district_button(district)
	var legend := PanelContainer.new()
	legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	legend.offset_left = 12
	legend.offset_top = -48
	legend.offset_right = 250
	legend.offset_bottom = -12
	legend.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.09, 0.12, 0.88), LINE, 9, 1))
	_map_stage.add_child(legend)
	var legend_margin := MarginContainer.new()
	legend_margin.add_theme_constant_override("margin_left", 10)
	legend_margin.add_theme_constant_override("margin_right", 10)
	legend_margin.add_theme_constant_override("margin_top", 6)
	legend_margin.add_theme_constant_override("margin_bottom", 6)
	legend.add_child(legend_margin)
	legend_margin.add_child(_label("● kamu   ◆ lokasi dipilih   ↗ state tersimpan lokal", 9, Color("d7e3df"), FONT_BODY))

func _add_district_button(district: String) -> void:
	var button := Button.new()
	button.text = district.to_upper()
	button.add_theme_font_override("font", load(FONT_BOLD))
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.05, 0.12, 0.16, 0.90), LINE, 8))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.22, 0.25, 0.96), TEAL, 8))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.14, 0.28, 0.28, 0.98), TEAL, 8))
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(122, 34)
	var pos: Vector2 = {
		"Town Square": Vector2(0.18, 0.23),
		"Residential": Vector2(0.50, 0.23),
		"Commercial": Vector2(0.82, 0.23),
		"Industrial": Vector2(0.18, 0.74),
		"Civic": Vector2(0.50, 0.74),
		"Park District": Vector2(0.82, 0.74)
	}[district]
	button.anchor_left = pos.x
	button.anchor_top = pos.y
	button.anchor_right = pos.x
	button.anchor_bottom = pos.y
	button.offset_left = -61
	button.offset_top = -17
	button.offset_right = 61
	button.offset_bottom = 17
	button.z_index = 4
	var district_name := district
	button.pressed.connect(func() -> void: _select_district(district_name))
	_map_stage.add_child(button)
	_district_buttons[district] = button

func _build_sidebar(body: Control) -> void:
	_sidebar_panel = PanelContainer.new()
	var sidebar := _sidebar_panel
	sidebar.name = "CityIntel"
	sidebar.custom_minimum_size = Vector2(338, 0)
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_stylebox_override("panel", _panel_style(SURFACE, LINE, 16, 1))
	body.add_child(sidebar)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	sidebar.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var kicker := _label("DISTRICT INTEL", 9, TEAL, FONT_BOLD)
	content.add_child(kicker)
	_details_title = _label("Town Square", 25, TEXT, FONT_TITLE)
	_details_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_details_title)
	_details_tag = _label("MEETING HUB", 10, GOLD, FONT_BOLD)
	content.add_child(_details_tag)
	_details_description = _label("", 11, MUTED, FONT_BODY)
	_details_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_description.custom_minimum_size = Vector2(0, 44)
	content.add_child(_details_description)
	var building_preview := TextureRect.new()
	building_preview.texture = BUILDING_SET
	building_preview.custom_minimum_size = Vector2(0, 72)
	building_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	building_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	building_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	building_preview.modulate = Color(1.0, 1.0, 1.0, 0.82)
	building_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(building_preview)
	_action_button = _make_action_button("Berinteraksi")
	content.add_child(_action_button)
	_action_button.pressed.connect(_primary_action)
	_secondary_button = _make_secondary_button("")
	content.add_child(_secondary_button)
	_secondary_button.pressed.connect(_secondary_action)
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", LINE)
	content.add_child(separator)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	content.add_child(stats)
	var stat_left := _stat_card("REPUTASI", "12", TEAL)
	stats.add_child(stat_left)
	_reputation_label = stat_left.find_child("Value", true, false) as Label
	var stat_right := _stat_card("SIM HOURS", "8", GOLD)
	stats.add_child(stat_right)
	_sim_label = _sim_label
	# The small stat cards below keep the economic state visible beside the map.
	var inventory_head := _label("INVENTORY  /  LEDGER", 9, MUTED, FONT_BOLD)
	content.add_child(inventory_head)
	_inventory_label = _label("", 10, TEXT, FONT_BODY)
	_inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inventory_label.custom_minimum_size = Vector2(0, 32)
	content.add_child(_inventory_label)
	var memory_head := _label("AI MEMORY  /  RELATIONSHIP", 9, MUTED, FONT_BOLD)
	content.add_child(memory_head)
	_memory_label = _label("", 10, TEXT, FONT_BODY)
	_memory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_memory_label.custom_minimum_size = Vector2(0, 56)
	content.add_child(_memory_label)
	_relationship_label = _label("", 9, TEAL, FONT_MEDIUM)
	content.add_child(_relationship_label)
	var npc_head := _label("RESIDENT DIRECTORY", 9, MUTED, FONT_BOLD)
	content.add_child(npc_head)
	_npc_box = VBoxContainer.new()
	_npc_box.add_theme_constant_override("separation", 4)
	content.add_child(_npc_box)
	for npc in npc_data:
		_add_npc_button(npc)
	var feed_head := _label("ACTIVITY FEED", 9, MUTED, FONT_BOLD)
	content.add_child(feed_head)
	_feed_scroll = ScrollContainer.new()
	_feed_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_feed_scroll.custom_minimum_size = Vector2(0, 70)
	content.add_child(_feed_scroll)
	_feed_box = VBoxContainer.new()
	_feed_box.add_theme_constant_override("separation", 4)
	_feed_scroll.add_child(_feed_box)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	content.add_child(footer)
	var catchup := _make_secondary_button("+1 JAM SIMULASI")
	catchup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(catchup)
	catchup.pressed.connect(_manual_catchup)
	var reduced := _make_secondary_button("MOTION")
	reduced.custom_minimum_size = Vector2(72, 30)
	footer.add_child(reduced)
	reduced.pressed.connect(func() -> void:
		_reduced_motion = not _reduced_motion
		reduced.text = "STILL" if _reduced_motion else "MOTION"
	)
	_notification_label = _label("", 10, GOLD, FONT_MEDIUM)
	_notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_notification_label)

func _layout_body() -> void:
	if not is_instance_valid(_body) or not is_instance_valid(_map_panel) or not is_instance_valid(_sidebar_panel):
		return
	var narrow := get_window().size.x < 760.0
	if narrow:
		_sidebar_panel.custom_minimum_size.x = 0.0
		_map_panel.anchor_left = 0.0
		_map_panel.anchor_top = 0.0
		_map_panel.anchor_right = 1.0
		_map_panel.anchor_bottom = 0.56
		_map_panel.offset_left = 0.0
		_map_panel.offset_top = 0.0
		_map_panel.offset_right = 0.0
		_map_panel.offset_bottom = -8.0
		_sidebar_panel.anchor_left = 0.0
		_sidebar_panel.anchor_top = 0.56
		_sidebar_panel.anchor_right = 1.0
		_sidebar_panel.anchor_bottom = 1.0
		_sidebar_panel.offset_left = 0.0
		_sidebar_panel.offset_top = 8.0
		_sidebar_panel.offset_right = 0.0
		_sidebar_panel.offset_bottom = 0.0
	else:
		_sidebar_panel.custom_minimum_size.x = 338.0
		_map_panel.anchor_left = 0.0
		_map_panel.anchor_top = 0.0
		_map_panel.anchor_right = 0.70
		_map_panel.anchor_bottom = 1.0
		_map_panel.offset_left = 0.0
		_map_panel.offset_top = 0.0
		_map_panel.offset_right = -8.0
		_map_panel.offset_bottom = 0.0
		_sidebar_panel.anchor_left = 0.70
		_sidebar_panel.anchor_top = 0.0
		_sidebar_panel.anchor_right = 1.0
		_sidebar_panel.anchor_bottom = 1.0
		_sidebar_panel.offset_left = 8.0
		_sidebar_panel.offset_top = 0.0
		_sidebar_panel.offset_right = 0.0
		_sidebar_panel.offset_bottom = 0.0

func _add_npc_button(npc: Dictionary) -> void:
	var button := Button.new()
	button.text = "  " + str(npc["name"]) + "   ·   " + str(npc["role"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", load(FONT_BODY))
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.05, 0.11, 0.15, 0.74), Color(0.10, 0.20, 0.24), 7))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.09, 0.19, 0.23, 0.90), TEAL, 7))
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 26)
	var npc_name := str(npc["name"])
	button.pressed.connect(func() -> void: _select_npc(npc_name))
	_npc_box.add_child(button)

func _select_district(district: String) -> void:
	_selected_district = district
	var info: Dictionary = district_info[district]
	if is_instance_valid(_details_title):
		_details_title.text = district
		_details_tag.text = str(info["tag"])
		_details_tag.add_theme_color_override("font_color", info["accent"])
		_details_description.text = str(info["description"])
		_action_button.text = str(info["action"])
		_secondary_button.visible = district in ["Commercial", "Industrial", "Park District"]
		_secondary_button.text = "Belanja · 40 CR" if district == "Commercial" else ("Produksi · 30 CR" if district == "Industrial" else "Pulihkan kebutuhan")
	_update_map_selection()
	_show_notification("Tujuan aktif: %s" % district)

func _update_map_selection() -> void:
	if not is_instance_valid(_selected_ring):
		return
	var button: Button = _district_buttons.get(_selected_district)
	if not is_instance_valid(button):
		return
	_selected_ring.position = button.position - Vector2(5, 5)
	_selected_ring.size = button.size + Vector2(10, 10)

func _select_npc(npc_name: String) -> void:
	_selected_npc = npc_name
	for npc in npc_data:
		if str(npc["name"]) == npc_name:
			var score := int(state["relationships"].get(npc_name, 0))
			_memory_label.text = "%s\n%s" % [str(npc["memory"]), str(npc["archetype"])]
			_relationship_label.text = "Trust & affinity  %02d / 100" % score
			break
	_update_npc_buttons()

func _update_npc_buttons() -> void:
	if not is_instance_valid(_npc_box):
		return
	for child in _npc_box.get_children():
		var button := child as Button
		if button == null:
			continue
		var active := _selected_npc in button.text
		button.add_theme_color_override("font_color", TEAL if active else MUTED)

func _primary_action() -> void:
	match _selected_district:
		"Town Square":
			_change_relationship(_selected_npc, 4)
			state["reputation"] = int(state["reputation"]) + 2
			_add_activity("Interaksi sosial", "+4 trust dengan %s · reputasi +2" % _selected_npc, TEAL)
		"Residential":
			_change_relationship(_selected_npc, 2)
			state["needs"]["social"] = clampi(int(state["needs"]["social"]) + 6, 0, 100)
			_add_activity("Kunjungan tetangga", "%s menyimpan memori baru tentangmu." % _selected_npc, GOLD)
		"Commercial":
			_work_shift()
		"Industrial":
			_manage_business()
		"Civic":
			_add_activity("Pengumuman civic", "Proposal taman malam lolos review manusia; AI tidak memiliki hak suara.", Color("c49bff"))
			state["reputation"] = int(state["reputation"]) + 1
		"Park District":
			state["needs"]["recreation"] = clampi(int(state["needs"]["recreation"]) + 18, 0, 100)
			state["needs"]["rest"] = clampi(int(state["needs"]["rest"]) + 8, 0, 100)
			_add_activity("Waktu istirahat", "Kebutuhan rekreasi pulih; Naya mencatat momen ini.", Color("83d58f"))
	_save_state()
	_update_all_ui()

func _secondary_action() -> void:
	match _selected_district:
		"Commercial":
			_buy_item()
		"Industrial":
			_produce_item()
		"Park District":
			_manual_catchup()
	_save_state()
	_update_all_ui()

func _work_shift() -> void:
	var wage := 120
	state["wallet"] = int(state["wallet"]) + wage
	state["reputation"] = int(state["reputation"]) + 1
	state["needs"]["income"] = clampi(int(state["needs"]["income"]) + 22, 0, 100)
	_append_ledger("WAGE", wage, "Commercial / shift toko")
	_add_activity("Shift selesai", "+%d CR masuk ledger · reputasi +1" % wage, GOLD)
	_show_notification("Upah tervalidasi: +%d CR" % wage)

func _buy_item() -> void:
	var price := 40
	if int(state["wallet"]) < price:
		_show_notification("Saldo tidak cukup untuk pembelian ini.")
		return
	state["wallet"] = int(state["wallet"]) - price
	state["inventory"]["Roti artisan"] = int(state["inventory"].get("Roti artisan", 0)) + 1
	_append_ledger("PURCHASE", -price, "Commercial / Roti artisan")
	_add_activity("Pembelian", "Roti artisan +1 · -%d CR · idempotency lokal aktif" % price, CORAL)
	_show_notification("Stok bertambah: Roti artisan +1")

func _manage_business() -> void:
	_add_activity("Business check", "Workshop merespons permintaan stok; manager AI tetap berada dalam budget.", BLUE)
	state["reputation"] = int(state["reputation"]) + 1
	_show_notification("Laporan bisnis diperbarui")

func _produce_item() -> void:
	var cost := 30
	if int(state["wallet"]) < cost:
		_show_notification("Budget produksi tidak mencukupi.")
		return
	state["wallet"] = int(state["wallet"]) - cost
	state["inventory"]["Komponen kota"] = int(state["inventory"].get("Komponen kota", 0)) + 1
	_append_ledger("PRODUCTION", -cost, "Industrial / workshop")
	_add_activity("Produksi selesai", "Komponen kota +1 · biaya operasional -%d CR" % cost, BLUE)

func _change_relationship(npc_name: String, amount: int) -> void:
	state["relationships"][npc_name] = clampi(int(state["relationships"].get(npc_name, 0)) + amount, 0, 100)
	_select_npc(npc_name)

func _manual_catchup() -> void:
	_apply_progression(1)
	state["simulation_hours"] = int(state["simulation_hours"]) + 1
	state["last_seen"] = int(Time.get_unix_time_from_system())
	_add_activity("Simulation tick", "+1 jam diproses secara event-driven · tidak ada aksi AI berisiko.", TEAL)
	_save_state()
	_update_all_ui()
	_show_notification("Simulasi maju 1 jam")

func _apply_progression(hours: int) -> void:
	var cycles := clampi(hours, 0, 6)
	if cycles <= 0:
		return
	var net := cycles * 9
	state["wallet"] = int(state["wallet"]) + net
	_append_ledger("OFFLINE_PROGRESS", net, "%d jam · pendapatan bisnis - biaya operasional" % cycles)
	state["needs"]["rest"] = clampi(int(state["needs"]["rest"]) - cycles * 2, 0, 100)
	state["needs"]["income"] = clampi(int(state["needs"]["income"]) + cycles * 2, 0, 100)
	_add_activity("Catch-up offline", "%d jam diproses: +%d CR net dan kebutuhan AI diperbarui." % [cycles, net], GOLD)

func _apply_offline_catchup() -> void:
	var now := int(Time.get_unix_time_from_system())
	var last := int(state.get("last_seen", 0))
	if last > 0:
		var elapsed_hours := clampi(int((now - last) / 3600), 0, 6)
		if elapsed_hours > 0:
			_apply_progression(elapsed_hours)
			state["simulation_hours"] = int(state["simulation_hours"]) + elapsed_hours
			_offline_banner.visible = true if is_instance_valid(_offline_banner) else false
			if is_instance_valid(_offline_text):
				_offline_text.text = "OFFLINE CATCH-UP  ·  %d jam simulasi diproses" % elapsed_hours
	state["last_seen"] = now

func _append_ledger(kind: String, amount: int, reference: String) -> void:
	var entry := {"id": "tx_%s_%s" % [str(Time.get_ticks_msec()), str(state["ledger"].size())], "type": kind, "amount": amount, "reference": reference}
	state["ledger"].push_front(entry)
	if state["ledger"].size() > 12:
		state["ledger"].pop_back()

func _add_activity(title: String, detail: String, accent: Color = TEAL) -> void:
	var event := {"title": title, "detail": detail, "accent": accent.to_html(false)}
	state["activity"].push_front(event)
	if state["activity"].size() > 18:
		state["activity"].pop_back()

func _update_all_ui() -> void:
	if not is_instance_valid(_wallet_label):
		return
	_wallet_label.text = "CR %d" % int(state["wallet"])
	_reputation_label.text = str(int(state["reputation"]))
	_sim_label.text = "SIM %02d JAM  /  LOCAL" % int(state["simulation_hours"])
	var inventory_text := ""
	for item in state["inventory"].keys():
		inventory_text += "• %s ×%d   " % [item, int(state["inventory"][item])]
	_inventory_label.text = inventory_text.strip_edges()
	_refresh_feed()
	_select_npc(_selected_npc)

func _refresh_feed() -> void:
	if not is_instance_valid(_feed_box):
		return
	for child in _feed_box.get_children():
		child.queue_free()
	for event in state["activity"]:
		var line := _label("%s\n%s" % [str(event["title"]), str(event["detail"])], 9, Color(event["accent"]), FONT_BODY)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(0, 28)
		_feed_box.add_child(line)

func _show_notification(text: String) -> void:
	if is_instance_valid(_notification_label):
		_notification_label.text = "↗  " + text
		var tween := create_tween()
		tween.tween_interval(3.0)
		tween.tween_callback(func() -> void:
			if is_instance_valid(_notification_label):
				_notification_label.text = "")

func _load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key in parsed.keys():
			state[key] = parsed[key]

func _save_state() -> void:
	state["last_seen"] = int(Time.get_unix_time_from_system())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))

func _label(text: String, size: int, color: Color, font_path: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", load(font_path))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_override("font", load(FONT_BOLD))
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", BG)
	button.add_theme_color_override("font_hover_color", BG)
	button.add_theme_stylebox_override("normal", _button_style(TEAL, TEAL, 8))
	button.add_theme_stylebox_override("hover", _button_style(Color("8bf1d9"), Color("8bf1d9"), 8))
	button.add_theme_stylebox_override("pressed", _button_style(Color("3da896"), Color("3da896"), 8))
	button.focus_mode = Control.FOCUS_NONE
	return button

func _make_secondary_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 30)
	button.add_theme_font_override("font", load(FONT_BOLD))
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.07, 0.14, 0.18, 0.8), LINE, 7))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.22, 0.26, 0.95), TEAL, 7))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.16, 0.30, 0.31, 0.98), TEAL, 7))
	button.focus_mode = Control.FOCUS_NONE
	return button

func _stat_card(title: String, value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(106, 48)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.12, 0.16, 0.78), Color(accent, 0.35), 8, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 9)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	margin.add_child(col)
	col.add_child(_label(title, 8, accent, FONT_BOLD))
	var val := _label(value, 15, TEXT, FONT_BOLD)
	val.name = "Value"
	col.add_child(val)
	return panel

func _panel_style(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _button_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := _panel_style(fill, border, radius, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style

func _ring_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.32, 0.83, 0.75, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.32, 0.83, 0.75, 0.24)
	style.shadow_size = 7
	return style
