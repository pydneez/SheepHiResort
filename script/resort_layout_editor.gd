class_name ResortLayoutEditor
extends Node2D
## Renovated Real-World Resort Layout & Pathways Architect.
## Activated in Phase 2 map when GameManager.is_layout_edit_mode is true.
## Features:
## - Full real-map view with camera panning & zooming
## - Buy multiple of the same building ($50 per building) using +, -, and $ buttons from assets/Ui.png
## - Hold-to-lift circle progress bar (~1s) preventing accidental clicks
## - Real-time confirmation floating bar with Tick (✓), Dollar ($), Minus (-), & Cross (✖) from assets/Ui.png
## - Real-map pathway paving & erasing with 32x32 grid snapping & Tile Map.png support
## - Fixed Top Navigation Bar with live Money HUD, "Save & Exit", and "Back to Lobby"

signal layout_saved()
signal layout_cancelled()

const UI_SPRITESHEET_PATH := "res://assets/UI/Ui.png"
const BUILDINGS_PATH := "res://assets/PhaseII_Map/Buildings1.png"
const CELL_SIZE: float = 32.0
const BUILDING_COST: int = 50

# =============================================================================
# NOTE FOR MANUAL EDITING: UI.PNG SPRITESHEET REGIONS (16x16 icons)
# File: res://assets/UI/Ui.png
# You can manually change any Rect2(x, y, width, height) region below if you
# want to use a different button color/row from assets/Ui.png!
# =============================================================================
# 1. Tick (✓) Button — Confirm moving an existing building (Col 2 & 3, Row 3)
const REGION_TICK_NORMAL := Rect2(32, 48, 16, 16)
const REGION_TICK_PRESSED := Rect2(48, 48, 16, 16)

# 2. Cross (✖) Button — Cancel move / Cancel purchase (Col 0 & 1, Row 4)
const REGION_CROSS_NORMAL := Rect2(0, 64, 16, 16)
const REGION_CROSS_PRESSED := Rect2(16, 64, 16, 16)

# 3. Plus (+) Button — Increase building purchase count (Col 0 & 1, Row 3)
# NOTE: Placeholder region from assets/Ui.png — edit here if replacing manually!
const REGION_PLUS_NORMAL := Rect2(0, 48, 16, 16)
const REGION_PLUS_PRESSED := Rect2(16, 48, 16, 16)

# 4. Minus (-) Button — Decrease purchase count / Remove building (Col 2 & 3, Row 4)
# NOTE: Placeholder region from assets/Ui.png — edit here if replacing manually!
const REGION_MINUS_NORMAL := Rect2(32, 64, 16, 16)
const REGION_MINUS_PRESSED := Rect2(48, 64, 16, 16)

# 5. Dollar ($) Button — Confirm building purchase for $50 (Col 2 & 3, Row 5)
# NOTE: Placeholder region from assets/Ui.png — edit here if replacing manually!
const REGION_DOLLAR_NORMAL := Rect2(32, 80, 16, 16)
const REGION_DOLLAR_PRESSED := Rect2(48, 80, 16, 16)

enum ToolMode {MOVE, PAVE, ERASE}
var current_tool: ToolMode = ToolMode.MOVE

var phase2_root: Phase2Resort = null
var facilities_container: Node2D = null
var pathways_renderer: PathwaysRenderer = null

# Snapshot for cancelling unsaved changes
var initial_money: int = 0
var initial_layout_snapshot: Dictionary = {}

# Active facility manipulation
var selected_facility: Facility = null
var original_facility_pos: Vector2 = Vector2.ZERO
var is_dragging_facility: bool = false
var is_pending_purchase_facility: bool = false
var drag_mouse_offset: Vector2 = Vector2.ZERO

# Per-facility purchase quantity selector in Left Panel: fac_id -> int (default 1)
var pending_buy_counts: Dictionary = {
	"cabin": 1,
	"restaurant": 1,
	"wool_salon": 1,
	"jail": 1,
}
var card_qty_labels: Dictionary = {}
var card_owned_labels: Dictionary = {}

# Hold-to-Lift mechanics (1.0s circle progress bar like the sheep)
var hold_target_facility: Facility = null
var is_holding_facility: bool = false
var facility_hold_progress: float = 0.0
const FACILITY_CHARGE_SPEED: float = 1.0 / 0.85 # ~0.85s to fill from 25% to 100%
const FACILITY_DECAY_SPEED: float = 2.5
var facility_hold_ring: Node2D = null

# UI Nodes
var canvas_layer: CanvasLayer = null
var top_nav_bar: PanelContainer = null
var left_panel: PanelContainer = null
var floating_widget: Node2D = null
var floating_btn_tick: TextureButton = null
var floating_btn_dollar: TextureButton = null
var floating_btn_minus: TextureButton = null
var floating_btn_cross: TextureButton = null
var floating_price_label: Label = null
var selection_pad: Node2D = null
var path_cursor: Node2D = null

# Left Panel & Top HUD Controls
var top_money_label: Label = null
var panel_money_label: Label = null
var status_toast_label: Label = null
var fac_header_label: Label = null
var btn_tool_move: Button = null
var btn_tool_pave: Button = null
var btn_tool_erase: Button = null
var btn_path_style: Button = null
var path_count_label: Label = null
var facility_card_map: Dictionary = {}
var hovered_facility: Facility = null

# Button textures from assets/Ui.png
var tex_tick_normal: AtlasTexture = null
var tex_tick_pressed: AtlasTexture = null
var tex_cross_normal: AtlasTexture = null
var tex_cross_pressed: AtlasTexture = null
var tex_plus_normal: AtlasTexture = null
var tex_plus_pressed: AtlasTexture = null
var tex_minus_normal: AtlasTexture = null
var tex_minus_pressed: AtlasTexture = null
var tex_dollar_normal: AtlasTexture = null
var tex_dollar_pressed: AtlasTexture = null

func setup(phase2: Phase2Resort, fac_container: Node2D, p_renderer: PathwaysRenderer) -> void:
	phase2_root = phase2
	facilities_container = fac_container
	pathways_renderer = p_renderer
	z_index = 50

	initial_money = GameManager.money
	initial_layout_snapshot = GameManager.resort_layout.duplicate(true)

	_load_ui_textures()
	_create_selection_pad()
	_create_facility_hold_ring()
	_create_path_cursor()
	_create_floating_widget()
	_build_ui()
	_refresh_money_and_counts()
	_hide_all_facility_labels()

	set_process_unhandled_input(true)

func _hide_all_facility_labels() -> void:
	if not is_instance_valid(facilities_container):
		return
	for child in facilities_container.get_children():
		if child is Facility:
			if is_instance_valid(child.name_label):
				child.name_label.visible = false
			if is_instance_valid(child.status_label):
				child.status_label.visible = false

func _load_ui_textures() -> void:
	var ui_tex := load(UI_SPRITESHEET_PATH) as Texture2D
	if not ui_tex:
		return

	# Tick (✓) Confirm Move Button
	tex_tick_normal = _make_atlas(ui_tex, REGION_TICK_NORMAL)
	tex_tick_pressed = _make_atlas(ui_tex, REGION_TICK_PRESSED)

	# Cross (✖) Cancel Button
	tex_cross_normal = _make_atlas(ui_tex, REGION_CROSS_NORMAL)
	tex_cross_pressed = _make_atlas(ui_tex, REGION_CROSS_PRESSED)

	# Plus (+) Button — NOTE: Uses REGION_PLUS_NORMAL / REGION_PLUS_PRESSED defined at top of file
	tex_plus_normal = _make_atlas(ui_tex, REGION_PLUS_NORMAL)
	tex_plus_pressed = _make_atlas(ui_tex, REGION_PLUS_PRESSED)

	# Minus (-) Button — NOTE: Uses REGION_MINUS_NORMAL / REGION_MINUS_PRESSED defined at top of file
	tex_minus_normal = _make_atlas(ui_tex, REGION_MINUS_NORMAL)
	tex_minus_pressed = _make_atlas(ui_tex, REGION_MINUS_PRESSED)

	# Dollar ($) Confirm Purchase Button — NOTE: Uses REGION_DOLLAR_NORMAL / REGION_DOLLAR_PRESSED defined at top of file
	tex_dollar_normal = _make_atlas(ui_tex, REGION_DOLLAR_NORMAL)
	tex_dollar_pressed = _make_atlas(ui_tex, REGION_DOLLAR_PRESSED)

func _make_atlas(sheet: Texture2D, region: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = sheet
	a.region = region
	return a

func _create_selection_pad() -> void:
	selection_pad = Node2D.new()
	selection_pad.name = "SelectionPad"
	selection_pad.visible = false
	selection_pad.z_index = -1
	add_child(selection_pad)
	selection_pad.draw.connect(_on_selection_pad_draw)

func _on_selection_pad_draw() -> void:
	if not is_instance_valid(selected_facility):
		return
	var fill_col := Color(1.0, 0.85, 0.25, 0.24) if is_pending_purchase_facility else Color(0.2, 0.8, 1.0, 0.22)
	var ring_col := Color(1.0, 0.9, 0.35, 0.9) if is_pending_purchase_facility else Color(0.3, 0.9, 1.0, 0.85)
	selection_pad.draw_circle(Vector2(0, -10), 75.0, fill_col)
	selection_pad.draw_arc(Vector2(0, -10), 75.0, 0, TAU, 36, ring_col, 3.0, true)

func _create_facility_hold_ring() -> void:
	facility_hold_ring = Node2D.new()
	facility_hold_ring.name = "FacilityHoldRing"
	facility_hold_ring.visible = false
	facility_hold_ring.z_index = 65
	add_child(facility_hold_ring)
	facility_hold_ring.draw.connect(_on_facility_hold_ring_draw)

func _on_facility_hold_ring_draw() -> void:
	if facility_hold_progress <= 0.0 or not is_instance_valid(hold_target_facility):
		return
	var r: float = 70.0
	var center := Vector2(0, -15)

	# Soft ground shadow ring under building
	facility_hold_ring.draw_circle(center, r + 4.0, Color(0.0, 0.0, 0.0, 0.3 * facility_hold_progress))
	# Background track ring
	facility_hold_ring.draw_arc(center, r, 0, TAU, 48, Color(0.12, 0.16, 0.22, 0.85), 5.0, true)
	# Active fill arc (starting at -PI/2 = top 12 o'clock, clockwise)
	var start_angle := -PI * 0.5
	var end_angle := start_angle + facility_hold_progress * TAU
	# Color shift: amber gold at 25% -> bright emerald/cyan at 100%
	var ring_color: Color = Color(1.0, 0.78, 0.2).lerp(Color(0.2, 1.0, 0.55), clampf((facility_hold_progress - 0.25) / 0.75, 0.0, 1.0))
	facility_hold_ring.draw_arc(center, r, start_angle, end_angle, 48, ring_color, 5.0, true)

func _create_path_cursor() -> void:
	path_cursor = Node2D.new()
	path_cursor.name = "PathCursor"
	path_cursor.visible = false
	path_cursor.z_index = 10
	add_child(path_cursor)
	path_cursor.draw.connect(_on_path_cursor_draw)

func _on_path_cursor_draw() -> void:
	if current_tool == ToolMode.MOVE:
		return
	var col: Color = Color(0.3, 1.0, 0.5, 0.8) if current_tool == ToolMode.PAVE else Color(1.0, 0.35, 0.35, 0.8)
	var fill_col: Color = Color(col.r, col.g, col.b, 0.25)
	var rect := Rect2(Vector2.ZERO, Vector2(CELL_SIZE, CELL_SIZE))
	path_cursor.draw_rect(rect, fill_col, true)
	path_cursor.draw_rect(rect, col, false, 2.0)

func _create_floating_widget() -> void:
	floating_widget = Node2D.new()
	floating_widget.name = "FloatingActionBar"
	floating_widget.visible = false
	floating_widget.z_index = 70
	add_child(floating_widget)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 48)
	panel.offset_left = -70.0
	panel.offset_top = -24.0
	panel.offset_right = 70.0
	panel.offset_bottom = 24.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.14, 0.2, 0.95)
	style.border_color = Color(0.85, 0.75, 0.45, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	floating_widget.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Price tag shown when confirming a new $50 building purchase on the map
	floating_price_label = Label.new()
	floating_price_label.text = "$%d" % BUILDING_COST
	floating_price_label.add_theme_font_size_override("font_size", 13)
	floating_price_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	floating_price_label.visible = false
	hbox.add_child(floating_price_label)

	# 1. Dollar ($) Button — Confirm purchasing a newly dragged building for $50
	# NOTE: Uses tex_dollar_normal / tex_dollar_pressed from assets/Ui.png
	floating_btn_dollar = _make_icon_button("ConfirmBuyBtn", tex_dollar_normal, tex_dollar_pressed, Vector2(30, 30), "Buy & Place Building ($%d)" % BUILDING_COST)
	floating_btn_dollar.pressed.connect(_on_confirm_facility_placement)
	floating_btn_dollar.visible = false
	hbox.add_child(floating_btn_dollar)

	# 2. Tick (✓) Button — Confirm moving an already-owned building
	floating_btn_tick = _make_icon_button("ConfirmMoveBtn", tex_tick_normal, tex_tick_pressed, Vector2(30, 30), "Confirm New Position (✓)")
	floating_btn_tick.pressed.connect(_on_confirm_facility_placement)
	hbox.add_child(floating_btn_tick)

	# 3. Minus (-) Button — Sell / Remove selected building (+$50 refund)
	# NOTE: Uses tex_minus_normal / tex_minus_pressed from assets/Ui.png
	floating_btn_minus = _make_icon_button("RemoveBuildingBtn", tex_minus_normal, tex_minus_pressed, Vector2(30, 30), "Remove / Sell Building (+$%d)" % BUILDING_COST)
	floating_btn_minus.pressed.connect(_on_remove_selected_facility)
	hbox.add_child(floating_btn_minus)

	# 4. Cross (✖) Button — Cancel movement or cancel pending purchase
	floating_btn_cross = _make_icon_button("CancelBtn", tex_cross_normal, tex_cross_pressed, Vector2(30, 30), "Cancel (✖)")
	floating_btn_cross.pressed.connect(_on_cancel_facility_placement)
	hbox.add_child(floating_btn_cross)

func _make_icon_button(btn_name: String, normal_tex: Texture2D, pressed_tex: Texture2D, min_size: Vector2, tip: String) -> TextureButton:
	var btn := TextureButton.new()
	btn.name = btn_name
	btn.texture_normal = normal_tex
	btn.texture_pressed = pressed_tex
	btn.texture_hover = pressed_tex
	btn.custom_minimum_size = min_size
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.tooltip_text = tip
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

func _build_ui() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "LayoutEditorCanvas"
	canvas_layer.layer = 15
	add_child(canvas_layer)

	_build_top_nav_bar()
	_build_left_panel()

func _build_top_nav_bar() -> void:
	top_nav_bar = PanelContainer.new()
	top_nav_bar.name = "TopNavBar"
	top_nav_bar.position = Vector2(346, 16)
	top_nav_bar.custom_minimum_size = Vector2(660, 44)
	top_nav_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.09, 0.12, 0.18, 0.95)
	top_style.border_color = Color(0.4, 0.6, 0.8, 0.85)
	top_style.set_border_width_all(2)
	top_style.set_corner_radius_all(8)
	top_style.shadow_color = Color(0, 0, 0, 0.4)
	top_style.shadow_size = 6
	top_nav_bar.add_theme_stylebox_override("panel", top_style)
	canvas_layer.add_child(top_nav_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 6)
	top_nav_bar.add_child(margin)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	margin.add_child(hb)

	var title := Label.new()
	title.text = "🏛️ RESORT ARCHITECT"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(title)

	top_money_label = Label.new()
	top_money_label.text = "💰 Funds: $%d" % GameManager.money
	top_money_label.add_theme_font_size_override("font_size", 14)
	top_money_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	top_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(top_money_label)

	var dev_money_btn := Button.new()
	dev_money_btn.text = "+$100 (Dev)"
	dev_money_btn.tooltip_text = "Dev helper: Add $100 to test buying buildings"
	dev_money_btn.focus_mode = Control.FOCUS_NONE
	dev_money_btn.pressed.connect(func():
		GameManager.money += 100
		_refresh_money_and_counts()
		_show_status_toast("Added +$100 dev funds!", Color(0.4, 1.0, 0.55))
	)
	hb.add_child(dev_money_btn)

	var top_btn_save := Button.new()
	top_btn_save.text = "💾 Save & Exit"
	top_btn_save.focus_mode = Control.FOCUS_NONE
	var save_s := StyleBoxFlat.new()
	save_s.bg_color = Color(0.18, 0.48, 0.28)
	save_s.border_color = Color(0.4, 0.95, 0.55)
	save_s.set_border_width_all(1)
	save_s.set_corner_radius_all(4)
	top_btn_save.add_theme_stylebox_override("normal", save_s)
	top_btn_save.pressed.connect(_on_save_and_exit)
	hb.add_child(top_btn_save)

	var top_btn_cancel := Button.new()
	top_btn_cancel.text = "✕ Back to Lobby"
	top_btn_cancel.focus_mode = Control.FOCUS_NONE
	var cancel_s := StyleBoxFlat.new()
	cancel_s.bg_color = Color(0.35, 0.18, 0.18)
	cancel_s.border_color = Color(0.9, 0.4, 0.4)
	cancel_s.set_border_width_all(1)
	cancel_s.set_corner_radius_all(4)
	top_btn_cancel.add_theme_stylebox_override("normal", cancel_s)
	top_btn_cancel.pressed.connect(_on_cancel_and_exit)
	hb.add_child(top_btn_cancel)

func _build_left_panel() -> void:
	left_panel = PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Set anchors to full vertical height along left edge
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 0.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 16.0
	left_panel.offset_top = 16.0
	left_panel.offset_right = 334.0
	left_panel.offset_bottom = -16.0
	left_panel.custom_minimum_size = Vector2(318, 736)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.12, 0.17, 0.95)
	panel_style.border_color = Color(0.4, 0.55, 0.7, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.shadow_color = Color(0, 0, 0, 0.45)
	panel_style.shadow_size = 8
	left_panel.add_theme_stylebox_override("panel", panel_style)
	canvas_layer.add_child(left_panel)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	left_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)

	# 1. Header & Money Balance
	var title_lbl := Label.new()
	title_lbl.text = "🏛️ FACILITY SHOP & LAYOUT"
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(title_lbl)

	panel_money_label = Label.new()
	panel_money_label.text = "💰 Balance: $%d  ($%d / building)" % [GameManager.money, BUILDING_COST]
	panel_money_label.add_theme_font_size_override("font_size", 12)
	panel_money_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	vb.add_child(panel_money_label)

	var sub_lbl := Label.new()
	sub_lbl.text = "Use [+]/[-] to choose amount & press [$] to buy.\nOr drag a card onto the map! Hold building ~1s to move."
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	vb.add_child(sub_lbl)

	status_toast_label = Label.new()
	status_toast_label.text = ""
	status_toast_label.visible = false
	status_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_toast_label.add_theme_font_size_override("font_size", 11)
	vb.add_child(status_toast_label)

	vb.add_child(_make_separator())

	# 2. Facilities Shop Section
	fac_header_label = Label.new()
	fac_header_label.text = "BUY & PLACE FACILITIES ($%d EACH)" % BUILDING_COST
	fac_header_label.add_theme_font_size_override("font_size", 11)
	fac_header_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	vb.add_child(fac_header_label)

	_build_facility_cards(vb)

	vb.add_child(_make_separator())

	# 3. Pathways Section
	var path_hdr := Label.new()
	path_hdr.text = "PATHWAY BUILDER"
	path_hdr.add_theme_font_size_override("font_size", 11)
	path_hdr.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	vb.add_child(path_hdr)

	var path_tools_box := HBoxContainer.new()
	path_tools_box.add_theme_constant_override("separation", 6)
	vb.add_child(path_tools_box)

	btn_tool_move = Button.new()
	btn_tool_move.text = "🖐️ Move"
	btn_tool_move.focus_mode = Control.FOCUS_NONE
	btn_tool_move.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tool_move.pressed.connect(_set_tool_mode.bind(ToolMode.MOVE))
	path_tools_box.add_child(btn_tool_move)

	btn_tool_pave = Button.new()
	btn_tool_pave.text = "🧱 Pave"
	btn_tool_pave.focus_mode = Control.FOCUS_NONE
	btn_tool_pave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tool_pave.pressed.connect(_set_tool_mode.bind(ToolMode.PAVE))
	path_tools_box.add_child(btn_tool_pave)

	btn_tool_erase = Button.new()
	btn_tool_erase.text = "🧹 Erase"
	btn_tool_erase.focus_mode = Control.FOCUS_NONE
	btn_tool_erase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tool_erase.pressed.connect(_set_tool_mode.bind(ToolMode.ERASE))
	path_tools_box.add_child(btn_tool_erase)

	var path_actions_box := HBoxContainer.new()
	path_actions_box.add_theme_constant_override("separation", 6)
	vb.add_child(path_actions_box)

	var btn_clear := Button.new()
	btn_clear.text = "🗑️ Clear All"
	btn_clear.focus_mode = Control.FOCUS_NONE
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.pressed.connect(_clear_all_pathways)
	path_actions_box.add_child(btn_clear)

	var btn_reset := Button.new()
	btn_reset.text = "🔄 Reset Promenade"
	btn_reset.focus_mode = Control.FOCUS_NONE
	btn_reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reset.pressed.connect(_reset_pathways_default)
	path_actions_box.add_child(btn_reset)

	path_count_label = Label.new()
	path_count_label.add_theme_font_size_override("font_size", 11)
	path_count_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
	vb.add_child(path_count_label)
	_refresh_path_count()

	vb.add_child(_make_separator())

	# 4. Save & Exit Actions
	var btn_save := Button.new()
	btn_save.text = "💾 Save & Return to Desk"
	btn_save.focus_mode = Control.FOCUS_NONE
	btn_save.custom_minimum_size = Vector2(0, 38)
	var save_style := StyleBoxFlat.new()
	save_style.bg_color = Color(0.18, 0.48, 0.28)
	save_style.border_color = Color(0.4, 0.95, 0.55)
	save_style.set_border_width_all(2)
	save_style.set_corner_radius_all(6)
	btn_save.add_theme_stylebox_override("normal", save_style)
	btn_save.pressed.connect(_on_save_and_exit)
	vb.add_child(btn_save)

	var btn_cancel := Button.new()
	btn_cancel.text = "✕ Cancel & Return"
	btn_cancel.focus_mode = Control.FOCUS_NONE
	btn_cancel.custom_minimum_size = Vector2(0, 30)
	btn_cancel.pressed.connect(_on_cancel_and_exit)
	vb.add_child(btn_cancel)

	_update_tool_buttons()

func _build_facility_cards(parent: VBoxContainer) -> void:
	var fac_defs := [
		{
			"id": "cabin",
			"display": "Cabin",
			"sub": "Lodge • Row 0",
			"row": 0,
			"color": Color(1.0, 0.65, 0.25)
		},
		{
			"id": "restaurant",
			"display": "Restaurant",
			"sub": "Dining • Row 7",
			"row": 7,
			"color": Color(0.35, 0.85, 0.45)
		},
		{
			"id": "wool_salon",
			"display": "Wool Salon",
			"sub": "Salon • Row 13",
			"row": 13,
			"color": Color(0.75, 0.55, 1.0)
		},
		{
			"id": "jail",
			"display": "Jail",
			"sub": "Deportation • Row 11",
			"row": 11,
			"color": Color(0.9, 0.35, 0.35)
		},
	]

	var bld_tex := load(BUILDINGS_PATH) as Texture2D

	for def in fac_defs:
		var fac_id: String = def["id"]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 82)
		var c_style := StyleBoxFlat.new()
		c_style.bg_color = Color(0.12, 0.16, 0.22, 0.92)
		c_style.border_color = def["color"]
		c_style.set_border_width_all(2)
		c_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", c_style)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		parent.add_child(card)

		var card_margin := MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 8)
		card_margin.add_theme_constant_override("margin_top", 6)
		card_margin.add_theme_constant_override("margin_right", 8)
		card_margin.add_theme_constant_override("margin_bottom", 6)
		card.add_child(card_margin)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		card_margin.add_child(hbox)

		# Thumbnail preview of row from Buildings1.png (draggable onto map!)
		if bld_tex:
			var icon_rect := TextureRect.new()
			icon_rect.custom_minimum_size = Vector2(52, 52)
			var atlas := AtlasTexture.new()
			atlas.atlas = bld_tex
			atlas.region = Rect2(0, def["row"] * 150, 150, 150)
			icon_rect.texture = atlas
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.tooltip_text = "Drag onto map to place a new %s ($%d)" % [def["display"], BUILDING_COST]
			icon_rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			icon_rect.gui_input.connect(_on_facility_card_gui_input.bind(fac_id))
			hbox.add_child(icon_rect)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 3)
		hbox.add_child(info)

		# Top row: Name + Owned count
		var top_row := HBoxContainer.new()
		info.add_child(top_row)

		var name_lbl := Label.new()
		name_lbl.text = def["display"]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		top_row.add_child(name_lbl)

		var owned_lbl := Label.new()
		owned_lbl.text = "Owned: 1"
		owned_lbl.add_theme_font_size_override("font_size", 11)
		owned_lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		top_row.add_child(owned_lbl)
		card_owned_labels[fac_id] = owned_lbl

		# Bottom row: [-] [Qty & Price] [+] and [$] Confirm Purchase Button (from assets/Ui.png)
		var buy_row := HBoxContainer.new()
		buy_row.alignment = BoxContainer.ALIGNMENT_BEGIN
		buy_row.add_theme_constant_override("separation", 6)
		info.add_child(buy_row)

		# Minus (-) Button — Placeholder from assets/Ui.png (see REGION_MINUS_NORMAL at top of script)
		var btn_minus := _make_icon_button(
			"MinusBtn_" + fac_id,
			tex_minus_normal,
			tex_minus_pressed,
			Vector2(24, 24),
			"Decrease quantity (-)"
		)
		btn_minus.pressed.connect(_on_adjust_buy_qty.bind(fac_id, -1))
		buy_row.add_child(btn_minus)

		# Quantity & Total Cost Label
		var qty_lbl := Label.new()
		qty_lbl.text = "x1 ($%d)" % BUILDING_COST
		qty_lbl.custom_minimum_size = Vector2(72, 0)
		qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		qty_lbl.add_theme_font_size_override("font_size", 12)
		qty_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		buy_row.add_child(qty_lbl)
		card_qty_labels[fac_id] = qty_lbl

		# Plus (+) Button — Placeholder from assets/Ui.png (see REGION_PLUS_NORMAL at top of script)
		var btn_plus := _make_icon_button(
			"PlusBtn_" + fac_id,
			tex_plus_normal,
			tex_plus_pressed,
			Vector2(24, 24),
			"Increase quantity (+)"
		)
		btn_plus.pressed.connect(_on_adjust_buy_qty.bind(fac_id, 1))
		buy_row.add_child(btn_plus)

		# Spacer
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_row.add_child(spacer)

		# Dollar ($) Button — Confirm Purchase from assets/Ui.png (see REGION_DOLLAR_NORMAL at top of script)
		var btn_buy := _make_icon_button(
			"DollarBuyBtn_" + fac_id,
			tex_dollar_normal,
			tex_dollar_pressed,
			Vector2(28, 28),
			"Confirm Purchase ($%d per building)" % BUILDING_COST
		)
		btn_buy.pressed.connect(_on_buy_facility_pressed.bind(fac_id))
		buy_row.add_child(btn_buy)

		facility_card_map[fac_id] = card

func _on_adjust_buy_qty(fac_id: String, delta_qty: int) -> void:
	var cur: int = pending_buy_counts.get(fac_id, 1)
	var next_qty: int = clampi(cur + delta_qty, 1, 9)
	pending_buy_counts[fac_id] = next_qty
	if card_qty_labels.has(fac_id):
		var lbl: Label = card_qty_labels[fac_id]
		lbl.text = "x%d ($%d)" % [next_qty, next_qty * BUILDING_COST]

func _on_buy_facility_pressed(fac_id: String) -> void:
	var qty: int = pending_buy_counts.get(fac_id, 1)
	var total_cost: int = qty * BUILDING_COST

	if GameManager.money < total_cost:
		_show_status_toast("⚠ Not enough money! Need $%d (Have $%d)" % [total_cost, GameManager.money], Color(1.0, 0.4, 0.4))
		return

	# If another facility was being moved/placed, confirm it first
	if is_instance_valid(selected_facility):
		_on_confirm_facility_placement()

	# Deduct cost
	GameManager.money -= total_cost

	# Spawn `qty` new instances of this building near the camera center
	var last_spawned: Facility = null
	var cam_center: Vector2 = phase2_root.camera.position if is_instance_valid(phase2_root) and is_instance_valid(phase2_root.camera) else Vector2(80, 50)
	for i in range(qty):
		var offset := Vector2((i % 3) * 96 - 48, int(i / 3.0) * 96)
		var spawn_pos := (cam_center + offset).snapped(Vector2(16, 16))
		last_spawned = phase2_root.create_facility_instance(fac_id, spawn_pos)

	# Reset card quantity back to 1
	pending_buy_counts[fac_id] = 1
	if card_qty_labels.has(fac_id):
		card_qty_labels[fac_id].text = "x1 ($%d)" % BUILDING_COST

	_sync_facilities_to_game_manager()
	_refresh_money_and_counts()
	_show_status_toast("✓ Purchased %dx %s (-$%d)! Move & press ✓ to place." % [qty, fac_id.capitalize(), total_cost], Color(0.4, 1.0, 0.55))

	# Select the newly created building so the player can immediately position it
	if is_instance_valid(last_spawned):
		is_pending_purchase_facility = false
		_select_and_start_moving(last_spawned)
		is_dragging_facility = false
		_update_selection_visuals()

func _count_owned_facilities(fac_id: String) -> int:
	if not is_instance_valid(facilities_container):
		return 0
	var count: int = 0
	for child in facilities_container.get_children():
		if child is Facility and phase2_root._matches_facility_id(child.facility_id, fac_id):
			if is_pending_purchase_facility and child == selected_facility:
				continue
			count += 1
	return count

func _refresh_money_and_counts() -> void:
	if is_instance_valid(top_money_label):
		top_money_label.text = "💰 Funds: $%d" % GameManager.money
	if is_instance_valid(panel_money_label):
		panel_money_label.text = "💰 Balance: $%d  ($%d / building)" % [GameManager.money, BUILDING_COST]

	var total_buildings: int = 0
	for fac_id in card_owned_labels.keys():
		var c: int = _count_owned_facilities(fac_id)
		total_buildings += c
		var lbl: Label = card_owned_labels[fac_id]
		if is_instance_valid(lbl):
			lbl.text = "Owned: %d" % c

	if is_instance_valid(fac_header_label):
		fac_header_label.text = "FACILITIES IN RESORT (%d) • $%d EACH" % [total_buildings, BUILDING_COST]

func _show_status_toast(msg: String, col: Color) -> void:
	if not is_instance_valid(status_toast_label):
		return
	status_toast_label.text = msg
	status_toast_label.add_theme_color_override("font_color", col)
	status_toast_label.visible = true

func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.3, 0.4, 0.52, 0.6)
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep

func _set_tool_mode(mode: ToolMode) -> void:
	current_tool = mode
	_update_tool_buttons()
	if current_tool != ToolMode.MOVE and is_instance_valid(selected_facility):
		_on_confirm_facility_placement()

func _update_tool_buttons() -> void:
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color(0.22, 0.45, 0.65)
	active_style.border_color = Color(0.65, 0.95, 1.0)
	active_style.set_border_width_all(2)
	active_style.set_corner_radius_all(4)

	var inactive_style := StyleBoxFlat.new()
	inactive_style.bg_color = Color(0.12, 0.16, 0.22)
	inactive_style.border_color = Color(0.3, 0.38, 0.48)
	inactive_style.set_border_width_all(1)
	inactive_style.set_corner_radius_all(4)

	btn_tool_move.add_theme_stylebox_override("normal", active_style if current_tool == ToolMode.MOVE else inactive_style)
	btn_tool_pave.add_theme_stylebox_override("normal", active_style if current_tool == ToolMode.PAVE else inactive_style)
	btn_tool_erase.add_theme_stylebox_override("normal", active_style if current_tool == ToolMode.ERASE else inactive_style)

# =============================================================================
# Facility Relocation, Drag-to-Buy & Floating Confirmation Bar
# =============================================================================

func _on_facility_card_gui_input(event: InputEvent, fac_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Dragging from a card spawns a new unpurchased preview building to place & buy ($50)
			if is_instance_valid(selected_facility):
				_on_confirm_facility_placement()

			var mouse_world := get_global_mouse_position()
			var new_fac := phase2_root.create_facility_instance(fac_id, mouse_world.snapped(Vector2(16, 16)))
			is_pending_purchase_facility = true
			_select_and_start_moving(new_fac)
			_show_status_toast("Drag to position, then click [$] above building to buy for $%d!" % BUILDING_COST, Color(1.0, 0.9, 0.4))
		else:
			if is_dragging_facility:
				is_dragging_facility = false
				_update_selection_visuals()

func _select_and_start_moving(fac: Facility) -> void:
	if selected_facility == fac and is_dragging_facility:
		return

	# If another facility was already selected, finalize it first
	if is_instance_valid(selected_facility) and selected_facility != fac:
		_on_confirm_facility_placement()

	selected_facility = fac
	original_facility_pos = fac.position
	is_dragging_facility = true
	drag_mouse_offset = Vector2.ZERO

	selected_facility.z_index = 60
	_update_selection_visuals()

func _lift_facility_up(fac: Facility) -> void:
	is_holding_facility = false
	facility_hold_progress = 0.0
	if is_instance_valid(facility_hold_ring):
		facility_hold_ring.visible = false
	hold_target_facility = null

	is_pending_purchase_facility = false
	_select_and_start_moving(fac)
	drag_mouse_offset = fac.position - get_global_mouse_position()

	# Little bounce / squash to signal it has been lifted
	if is_instance_valid(fac.visual_root):
		var squish := create_tween()
		squish.tween_property(fac.visual_root, "scale", Vector2(1.15, 1.15), 0.08)
		squish.tween_property(fac.visual_root, "scale", Vector2(1.0, 1.0), 0.1)

func _on_confirm_facility_placement() -> void:
	if not is_instance_valid(selected_facility):
		return

	# If this is a pending purchase dragged from the Left Panel, charge $50 now!
	if is_pending_purchase_facility:
		if GameManager.money < BUILDING_COST:
			_show_status_toast("⚠ Not enough money! Need $%d (Have $%d)" % [BUILDING_COST, GameManager.money], Color(1.0, 0.4, 0.4))
			return
		GameManager.money -= BUILDING_COST
		is_pending_purchase_facility = false
		_show_status_toast("✓ Purchased %s (-$%d)!" % [selected_facility.display_name, BUILDING_COST], Color(0.4, 1.0, 0.55))

	# Bounce feedback animation
	var t := create_tween()
	t.tween_property(selected_facility.visual_root, "scale", Vector2(1.12, 0.9), 0.08)
	t.tween_property(selected_facility.visual_root, "scale", Vector2(1.0, 1.0), 0.1)

	selected_facility.z_index = 0
	selected_facility = null
	is_dragging_facility = false
	_hide_selection_visuals()
	_sync_facilities_to_game_manager()
	_refresh_money_and_counts()

func _on_cancel_facility_placement() -> void:
	if not is_instance_valid(selected_facility):
		return

	if is_pending_purchase_facility:
		# Discard unpurchased preview building without charging money
		var to_remove := selected_facility
		selected_facility = null
		is_dragging_facility = false
		is_pending_purchase_facility = false
		_hide_selection_visuals()
		if is_instance_valid(facilities_container):
			facilities_container.remove_child(to_remove)
		to_remove.queue_free()
		_refresh_money_and_counts()
		_show_status_toast("Purchase cancelled.", Color(0.8, 0.8, 0.85))
		return

	# Owned building: slide back to original position
	var t := create_tween()
	t.tween_property(selected_facility, "position", original_facility_pos, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	selected_facility.z_index = 0
	selected_facility = null
	is_dragging_facility = false
	_hide_selection_visuals()

func _on_remove_selected_facility() -> void:
	if not is_instance_valid(selected_facility):
		return

	if is_pending_purchase_facility:
		_on_cancel_facility_placement()
		return

	var fac_name := selected_facility.display_name
	var to_remove := selected_facility
	selected_facility = null
	is_dragging_facility = false
	_hide_selection_visuals()

	if is_instance_valid(facilities_container):
		facilities_container.remove_child(to_remove)
	to_remove.queue_free()

	GameManager.money += BUILDING_COST
	_sync_facilities_to_game_manager()
	_refresh_money_and_counts()
	_show_status_toast("Sold %s (+$%d refunded)." % [fac_name, BUILDING_COST], Color(1.0, 0.85, 0.35))

func _update_selection_visuals() -> void:
	if not is_instance_valid(selected_facility):
		_hide_selection_visuals()
		return

	selection_pad.visible = true
	selection_pad.global_position = selected_facility.global_position
	selection_pad.queue_redraw()

	# Toggle floating buttons depending on whether this is a new $50 purchase or a free move
	if is_instance_valid(floating_price_label):
		floating_price_label.visible = is_pending_purchase_facility
	if is_instance_valid(floating_btn_dollar):
		floating_btn_dollar.visible = is_pending_purchase_facility
	if is_instance_valid(floating_btn_tick):
		floating_btn_tick.visible = not is_pending_purchase_facility
	if is_instance_valid(floating_btn_minus):
		floating_btn_minus.visible = not is_pending_purchase_facility

	floating_widget.visible = true
	floating_widget.global_position = selected_facility.global_position + Vector2(0, -145.0)

func _hide_selection_visuals() -> void:
	if is_instance_valid(selection_pad):
		selection_pad.visible = false
	if is_instance_valid(floating_widget):
		floating_widget.visible = false

func _sync_facilities_to_game_manager() -> void:
	if not is_instance_valid(facilities_container):
		return
	var fac_dict: Dictionary = {}
	var fac_list: Array = []
	for child in facilities_container.get_children():
		if child is Facility:
			if is_pending_purchase_facility and child == selected_facility:
				continue
			fac_dict[child.name] = child.position
			fac_dict[child.facility_id] = child.position
			fac_list.append({
				"name": child.name,
				"facility_id": child.facility_id,
				"display_name": child.display_name,
				"position": child.position,
				"building_row": child.building_row,
				"base_cycle_time": child.base_cycle_time,
				"base_payout": child.base_payout,
			})
	GameManager.resort_layout["facilities"] = fac_dict
	GameManager.resort_layout["facility_instances"] = fac_list

# =============================================================================
# Input Processing: Facility Clicking, Dragging & Pathway Painting
# =============================================================================

func _process(delta: float) -> void:
	if not visible:
		return

	var mouse_world := get_global_mouse_position()

	# 1. Update hold-to-lift charge
	_handle_facility_hold(delta)

	# 2. Update dragged facility position
	if is_dragging_facility and is_instance_valid(selected_facility):
		selected_facility.position = (mouse_world + drag_mouse_offset).snapped(Vector2(16, 16))
		_update_selection_visuals()

	# 3. Update path cursor in Pave / Erase mode
	if current_tool != ToolMode.MOVE:
		var cell := GameManager.world_to_path_cell(mouse_world)
		path_cursor.visible = true
		path_cursor.global_position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
		path_cursor.queue_redraw()
	else:
		path_cursor.visible = false

	# 4. Update facility hover label pop-up
	_update_facility_hover(mouse_world)

func _update_facility_hover(mouse_world: Vector2) -> void:
	var target: Facility = null
	if not is_dragging_facility:
		target = _get_facility_at_point(mouse_world)

	if target != hovered_facility:
		if is_instance_valid(hovered_facility):
			if is_instance_valid(hovered_facility.name_label):
				hovered_facility.name_label.visible = false
			if is_instance_valid(hovered_facility.status_label):
				hovered_facility.status_label.visible = false

		hovered_facility = target

		if is_instance_valid(hovered_facility):
			if is_instance_valid(hovered_facility.name_label):
				hovered_facility.name_label.visible = true
			if is_instance_valid(hovered_facility.status_label):
				hovered_facility.status_label.visible = true

func _handle_facility_hold(delta: float) -> void:
	if is_holding_facility and is_instance_valid(hold_target_facility):
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_holding_facility = false
		else:
			var mouse_world := get_global_mouse_position()
			if hold_target_facility.is_point_inside(mouse_world):
				facility_hold_progress = minf(facility_hold_progress + delta * FACILITY_CHARGE_SPEED, 1.0)
				facility_hold_ring.global_position = hold_target_facility.global_position
				facility_hold_ring.visible = true
				facility_hold_ring.queue_redraw()
				if facility_hold_progress >= 1.0:
					_lift_facility_up(hold_target_facility)
					return
			else:
				facility_hold_progress = maxf(facility_hold_progress - delta * FACILITY_DECAY_SPEED, 0.0)
	else:
		if facility_hold_progress > 0.0:
			facility_hold_progress = maxf(facility_hold_progress - delta * FACILITY_DECAY_SPEED, 0.0)
			if is_instance_valid(facility_hold_ring):
				facility_hold_ring.queue_redraw()
				if facility_hold_progress <= 0.0:
					facility_hold_ring.visible = false
					hold_target_facility = null

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_world := get_global_mouse_position()

		if event.pressed:
			if current_tool == ToolMode.MOVE:
				var clicked_fac := _get_facility_at_point(mouse_world)
				if clicked_fac:
					# If already selected and floating bar is active, allow immediate drag
					if selected_facility == clicked_fac:
						is_dragging_facility = true
						drag_mouse_offset = clicked_fac.position - mouse_world
						get_viewport().set_input_as_handled()
						return

					# Otherwise start the 1.0s hold-to-lift charge
					hold_target_facility = clicked_fac
					is_holding_facility = true
					facility_hold_progress = 0.25 # starts at 25% like sheep
					facility_hold_ring.global_position = clicked_fac.global_position
					facility_hold_ring.visible = true
					facility_hold_ring.queue_redraw()
					get_viewport().set_input_as_handled()
					return

			if current_tool == ToolMode.PAVE:
				_paint_path_tile(mouse_world)
				get_viewport().set_input_as_handled()
			elif current_tool == ToolMode.ERASE:
				_erase_path_tile(mouse_world)
				get_viewport().set_input_as_handled()

		else:
			# Mouse released: cancel hold or stop dragging
			if is_holding_facility:
				is_holding_facility = false
			if is_dragging_facility:
				is_dragging_facility = false
				_update_selection_visuals()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_world := get_global_mouse_position()
		if current_tool == ToolMode.PAVE:
			_paint_path_tile(mouse_world)
		elif current_tool == ToolMode.ERASE:
			_erase_path_tile(mouse_world)

func _get_facility_at_point(point: Vector2) -> Facility:
	if not is_instance_valid(facilities_container):
		return null
	var facs := facilities_container.get_children()
	facs.reverse()
	for child in facs:
		if child is Facility and child.is_point_inside(point):
			return child
	return null

# =============================================================================
# Pathway Operations
# =============================================================================

func _paint_path_tile(world_pos: Vector2) -> void:
	var cell := GameManager.world_to_path_cell(world_pos)
	if not GameManager.path_cell_lookup.has(cell):
		GameManager.path_cell_lookup[cell] = true
		if not GameManager.resort_layout.has("pathways"):
			GameManager.resort_layout["pathways"] = []
		GameManager.resort_layout["pathways"].append(cell)
		if is_instance_valid(pathways_renderer):
			pathways_renderer.refresh()
		_refresh_path_count()

func _erase_path_tile(world_pos: Vector2) -> void:
	var cell := GameManager.world_to_path_cell(world_pos)
	if GameManager.path_cell_lookup.has(cell):
		GameManager.path_cell_lookup.erase(cell)
		if GameManager.resort_layout.has("pathways"):
			GameManager.resort_layout["pathways"].erase(cell)
		if is_instance_valid(pathways_renderer):
			pathways_renderer.refresh()
		_refresh_path_count()

func _clear_all_pathways() -> void:
	GameManager.path_cell_lookup.clear()
	GameManager.resort_layout["pathways"] = []
	if is_instance_valid(pathways_renderer):
		pathways_renderer.refresh()
	_refresh_path_count()

func _reset_pathways_default() -> void:
	var saved_instances: Array = GameManager.resort_layout.get("facility_instances", []).duplicate(true)
	GameManager.resort_layout.clear()
	GameManager.init_default_layout()
	if not saved_instances.is_empty():
		GameManager.resort_layout["facility_instances"] = saved_instances
	if is_instance_valid(pathways_renderer):
		pathways_renderer.refresh()
	_refresh_path_count()

func _refresh_path_count() -> void:
	if is_instance_valid(path_count_label):
		var count: int = GameManager.path_cell_lookup.size()
		path_count_label.text = "Path Tiles Placed: %d" % count

# =============================================================================
# Save & Exit Operations
# =============================================================================

func _on_save_and_exit() -> void:
	if is_instance_valid(selected_facility):
		if is_pending_purchase_facility:
			# Cancel unconfirmed drag preview before saving
			_on_cancel_facility_placement()
		else:
			_on_confirm_facility_placement()

	_sync_facilities_to_game_manager()

	layout_saved.emit()
	GameManager.is_layout_edit_mode = false
	GameManager.change_scene("res://scene/front_desk.tscn")

func _on_cancel_and_exit() -> void:
	# Restore money & layout snapshot from before opening the editor
	GameManager.money = initial_money
	GameManager.resort_layout = initial_layout_snapshot.duplicate(true)
	GameManager.path_cell_lookup.clear()
	for cell in GameManager.resort_layout.get("pathways", []):
		if cell is Vector2i:
			GameManager.path_cell_lookup[cell] = true

	layout_cancelled.emit()
	GameManager.is_layout_edit_mode = false
	GameManager.change_scene("res://scene/front_desk.tscn")
