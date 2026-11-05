class_name ResortLayoutEditor
extends Node2D
## Interactive in-world Resort Layout & Pathway Architect.
## Features:
## - Left Panel matching the reference UI: single Coin Icon + Balance (with pending "-Cost" preview),
##   2-column scrollable Facility Grid with hover description panel (Combo Skill & Flavor Text),
##   streamlined Pathway Builder ("Draw", "- Erase", "Clear All"), and Save/Cancel actions.
## - On-map Land Sale Signs on locked quarters with click-to-confirm Tick/Cross buttons
##   that automatically close when the mouse moves away.
## - Facility storage inventory ("Owned : X" tracks unplaced buildings in storage; removing a
##   facility from the map returns it to Owned storage rather than selling it).
## - Live 220px Combo Skill range circle and neighbor synergy highlights while placing buildings.

signal layout_saved()
signal layout_cancelled()

const UI_SHEET_PATH := "res://assets/UI/UI_pack.png"
const CELL_SIZE: float = 32.0
const FACILITY_HOLD_DURATION: float = 0.45
const FACILITY_CHARGE_SPEED: float = 1.0 / FACILITY_HOLD_DURATION
const FACILITY_DECAY_SPEED: float = 2.5
const SIGN_AUTO_CLOSE_RADIUS: float = 115.0

enum ToolMode {
	MOVE,
	DRAW,
	ERASE,
}

var phase2_root: Phase2Resort = null
var facilities_container: Node2D = null
var pathways_renderer: PathwaysRenderer = null

var current_tool: ToolMode = ToolMode.MOVE

# Snapshot of state when entering Edit Mode so "Cancel" can revert everything cleanly
var initial_money: int = 0
var initial_layout_snapshot: Dictionary = {}

# Facility selection, hold-to-lift & dragging state
var selected_facility: Facility = null
var is_pending_purchase_facility: bool = false
var is_pending_stored_placement: bool = false
var pending_facility_id: String = ""
var pending_purchase_cost: int = 0
var original_facility_pos: Vector2 = Vector2.ZERO
var is_dragging_facility: bool = false
var drag_mouse_offset: Vector2 = Vector2.ZERO

# Hold-to-lift state
var hold_target_facility: Facility = null
var is_holding_facility: bool = false
var facility_hold_progress: float = 0.0
var facility_hold_ring: Node2D = null
var hovered_facility: Facility = null

# In-world visual overlays
var land_grid_overlay: Node2D = null
var selection_pad: Node2D = null
var floating_widget: Node2D = null
var floating_combo_label: Label = null
var floating_btn_tick: TextureButton = null
var floating_btn_cross: TextureButton = null
var floating_btn_minus: TextureButton = null
var path_cursor: Node2D = null

# On-map Land Sale Signs (quarter_idx -> Dictionary of sign nodes & state)
var land_signs_root: Node2D = null
var land_signs: Dictionary = {}
var active_confirm_quarter: int = 0

# UI Layer & Left Panel controls
var ui_layer: CanvasLayer = null
var left_panel: PanelContainer = null
var pending_cost_label: Label = null
var balance_label: Label = null
var status_toast_label: Label = null
var fac_header_label: Label = null
var path_count_label: Label = null
var btn_tool_draw: Button = null
var btn_tool_erase: Button = null

# Hover Description Panel controls
var hover_desc_panel: PanelContainer = null
var hover_icon_rect: TextureRect = null
var hover_name_label: Label = null
var hover_desc_label: Label = null
var hover_combo_title_label: Label = null
var hover_combo_desc_label: Label = null
var hover_flavor_label: Label = null
var hovered_card_fac_id: String = ""

# Card references (facility_id -> Dictionary of card UI nodes)
var facility_cards: Dictionary = {}

# Preloaded UI AtlasTextures
var tex_tick_normal: AtlasTexture
var tex_tick_pressed: AtlasTexture
var tex_cross_normal: AtlasTexture
var tex_cross_pressed: AtlasTexture
var tex_minus_normal: AtlasTexture
var tex_minus_pressed: AtlasTexture

func setup(root: Phase2Resort, fac_container: Node2D, path_renderer: PathwaysRenderer) -> void:
	phase2_root = root
	facilities_container = fac_container
	pathways_renderer = path_renderer

	initial_money = GameManager.money
	initial_layout_snapshot = GameManager.resort_layout.duplicate(true)

	_build_ui_atlas_textures()
	_build_world_overlays()
	_build_land_sale_signs()
	_build_editor_ui()
	_prepare_facilities_for_editing()
	_refresh_money_and_counts()

# =============================================================================
# AtlasTexture Builders (from assets/UI/UI_pack.png)
# =============================================================================

func _build_ui_atlas_textures() -> void:
	tex_tick_normal = UIPack.make_icon_atlas("tick", false)
	tex_tick_pressed = UIPack.make_icon_atlas("tick", true)
	tex_cross_normal = UIPack.make_icon_atlas("cross", false)
	tex_cross_pressed = UIPack.make_icon_atlas("cross", true)
	tex_minus_normal = UIPack.make_icon_atlas("minus", false)
	tex_minus_pressed = UIPack.make_icon_atlas("minus", true)

func _make_icon_button(
	btn_name: String,
	normal_tex: Texture2D,
	pressed_tex: Texture2D,
	min_size: Vector2,
	tooltip: String
) -> TextureButton:
	var btn := TextureButton.new()
	btn.name = btn_name
	btn.texture_normal = normal_tex
	btn.texture_pressed = pressed_tex
	btn.texture_hover = normal_tex
	btn.custom_minimum_size = min_size
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.tooltip_text = tooltip
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

func _make_building_atlas(sheet_path: String, row: int) -> AtlasTexture:
	var tex := load(sheet_path) as Texture2D
	if not tex:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(0, row * 150, 150, 150)
	return atlas

# =============================================================================
# World Overlays: Locked Land Shading, Combo Radius Ring & Floating Bar
# =============================================================================

func _build_world_overlays() -> void:
	# 0. Subtle Land Boundary & Locked Quarter Shading Overlay
	land_grid_overlay = Node2D.new()
	land_grid_overlay.name = "LandGridOverlay"
	land_grid_overlay.z_index = -2
	land_grid_overlay.draw.connect(_draw_land_grid_overlay)
	add_child(land_grid_overlay)

	# 1. Selection Footprint Pad + 220px Combo Skill Radius Ring & Neighbor Synergy Highlights
	selection_pad = Node2D.new()
	selection_pad.name = "SelectionPad"
	selection_pad.z_index = 45
	selection_pad.visible = false
	selection_pad.draw.connect(_draw_selection_pad_and_combo)
	add_child(selection_pad)

	# 2. Hold-to-Lift Radial Progress Ring
	facility_hold_ring = Node2D.new()
	facility_hold_ring.name = "FacilityHoldRing"
	facility_hold_ring.z_index = 90
	facility_hold_ring.visible = false
	facility_hold_ring.draw.connect(_draw_facility_hold_ring)
	add_child(facility_hold_ring)

	# 3. Floating Confirmation Bar above Selected Facility (Combo text above, buttons below)
	floating_widget = Node2D.new()
	floating_widget.name = "FloatingConfirmWidget"
	floating_widget.z_index = 100
	floating_widget.visible = false
	add_child(floating_widget)

	var vbox_float := VBoxContainer.new()
	vbox_float.position = Vector2(-130, -78)
	vbox_float.custom_minimum_size = Vector2(260, 0)
	vbox_float.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox_float.add_theme_constant_override("separation", 6)
	floating_widget.add_child(vbox_float)

	floating_combo_label = Label.new()
	floating_combo_label.name = "FloatingComboLabel"
	floating_combo_label.text = ""
	floating_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floating_combo_label.add_theme_font_size_override("font_size", 18)
	floating_combo_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	floating_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	floating_combo_label.add_theme_constant_override("outline_size", 4)
	vbox_float.add_child(floating_combo_label)

	var pill_center := CenterContainer.new()
	vbox_float.add_child(pill_center)

	var pill_panel := PanelContainer.new()
	pill_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	UIPack.style_panel(pill_panel, "wood_frame_dark", Vector4(10, 6, 10, 6))
	pill_center.add_child(pill_panel)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	pill_panel.add_child(hbox)

	# Tick (✓) Button — Confirm Placement / Purchase
	floating_btn_tick = _make_icon_button(
		"ConfirmTickButton",
		tex_tick_normal,
		tex_tick_pressed,
		Vector2(34, 34),
		"Confirm Placement (✓)"
	)
	floating_btn_tick.pressed.connect(_on_confirm_facility_placement)
	hbox.add_child(floating_btn_tick)

	# Cross (✕) Button — Cancel Move / Discard Preview
	floating_btn_cross = _make_icon_button(
		"CancelCrossButton",
		tex_cross_normal,
		tex_cross_pressed,
		Vector2(34, 34),
		"Cancel (✕)"
	)
	floating_btn_cross.pressed.connect(_on_cancel_facility_placement)
	hbox.add_child(floating_btn_cross)

	# Minus (-) Button — Store Facility back into Owned Inventory (Not Sold)
	floating_btn_minus = _make_icon_button(
		"StoreFacilityMinusButton",
		tex_minus_normal,
		tex_minus_pressed,
		Vector2(34, 34),
		"Remove from Map & Store in Owned (+1)"
	)
	floating_btn_minus.pressed.connect(_on_store_selected_facility)
	hbox.add_child(floating_btn_minus)

	# 4. Pathway Brush Tile Cursor
	path_cursor = Node2D.new()
	path_cursor.name = "PathTileCursor"
	path_cursor.z_index = 40
	path_cursor.visible = false
	path_cursor.draw.connect(_draw_path_cursor)
	add_child(path_cursor)

func _draw_land_grid_overlay() -> void:
	for cy in range(GameManager.MAP_MIN_CELL_Y, GameManager.MAP_MAX_CELL_Y + 1):
		for cx in range(GameManager.MAP_MIN_CELL_X, GameManager.MAP_MAX_CELL_X + 1):
			var cell := Vector2i(cx, cy)
			var rect := Rect2(Vector2(cx * CELL_SIZE, cy * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var owned := GameManager.is_land_cell_unlocked(cell)
			if not owned:
				var q_idx := GameManager.get_quarter_for_cell(cell)
				var is_active_q := (q_idx == active_confirm_quarter and active_confirm_quarter > 0)
				var fill_col := Color(0.2, 0.35, 0.2, 0.25) if is_active_q else Color(0.05, 0.07, 0.1, 0.42)
				land_grid_overlay.draw_rect(rect, fill_col, true)
				land_grid_overlay.draw_rect(rect, Color(1.0, 0.85, 0.4, 0.14), false, 1.0)

	var map_rect := Rect2(
		Vector2(GameManager.MAP_MIN_CELL_X * CELL_SIZE, GameManager.MAP_MIN_CELL_Y * CELL_SIZE),
		Vector2(
			(GameManager.MAP_MAX_CELL_X - GameManager.MAP_MIN_CELL_X + 1) * CELL_SIZE,
			(GameManager.MAP_MAX_CELL_Y - GameManager.MAP_MIN_CELL_Y + 1) * CELL_SIZE
		)
	)
	land_grid_overlay.draw_rect(map_rect, Color(1.0, 0.85, 0.4, 0.4), false, 2.0)

func _draw_selection_pad_and_combo() -> void:
	if not is_instance_valid(selected_facility):
		return

	var is_valid := is_facility_placement_valid(selected_facility, selected_facility.position)
	var rect: Rect2 = selected_facility.get_selection_rect() if selected_facility.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
	var fill_col := Color(0.2, 0.95, 0.4, 0.22) if is_valid else Color(1.0, 0.25, 0.25, 0.32)
	var border_col := Color(0.3, 1.0, 0.45, 0.95) if is_valid else Color(1.0, 0.3, 0.3, 0.95)
	selection_pad.draw_rect(rect, fill_col, true)
	selection_pad.draw_rect(rect, border_col, false, 3.0)

	# Draw 220px Combo Skill Radius Circle (dashed segments)
	var fac_id: String = selected_facility.facility_id
	if fac_id != "main_building" and fac_id != "jail":
		var radius: float = GameManager.COMBO_RANGE
		var center := rect.get_center()
		selection_pad.draw_circle(center, radius, Color(0.35, 0.85, 1.0, 0.08))
		var segs: int = 48
		for i in range(segs):
			if i % 2 == 0:
				var a1: float = (TAU * float(i)) / float(segs)
				var a2: float = (TAU * float(i + 1)) / float(segs)
				selection_pad.draw_arc(center, radius, a1, a2, 6, Color(0.45, 0.9, 1.0, 0.75), 2.5)

		# Highlight affected nearby buildings (without connecting lines)
		var all_facs: Array = facilities_container.get_children() if is_instance_valid(facilities_container) else []
		var combo_res: Dictionary = GameManager.calculate_facility_combo(
			fac_id,
			selected_facility.position,
			all_facs,
			selected_facility
		)
		var neighbors: Array = combo_res.get("neighbors", [])
		var font: Font = UIPack.get_font("base")
		for item in neighbors:
			var n_node: Node2D = item.get("node")
			var delta_val: int = int(item.get("delta", 0))
			if is_instance_valid(n_node):
				var rel_pos: Vector2 = n_node.global_position - selection_pad.global_position
				var is_pos: bool = delta_val >= 0
				var syn_col := Color(0.25, 1.0, 0.45, 0.9) if is_pos else Color(1.0, 0.3, 0.3, 0.9)
				var syn_fill := Color(0.25, 1.0, 0.45, 0.2) if is_pos else Color(1.0, 0.3, 0.3, 0.22)
				
				var n_sel_rect: Rect2 = n_node.get_selection_rect() if n_node.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
				var n_rect := Rect2(rel_pos + n_sel_rect.position, n_sel_rect.size)
				selection_pad.draw_rect(n_rect, syn_fill, true)
				selection_pad.draw_rect(n_rect, syn_col, false, 3.0)
				if font:
					var badge_str: String = ("+$%d" % delta_val) if delta_val >= 0 else ("-$%d" % abs(delta_val))
					var badge_y := rel_pos.y + n_sel_rect.position.y - 12
					selection_pad.draw_string_outline(
						font,
						Vector2(rel_pos.x - 28, badge_y),
						badge_str,
						HORIZONTAL_ALIGNMENT_CENTER,
						-1,
						20,
						5,
						Color(0, 0, 0, 0.95)
					)
					selection_pad.draw_string(
						font,
						Vector2(rel_pos.x - 28, badge_y),
						badge_str,
						HORIZONTAL_ALIGNMENT_CENTER,
						-1,
						20,
						syn_col
					)

	# Corner brackets
	var c_len: float = clampf(rect.size.x * 0.22, 10.0, 18.0)
	var tl := rect.position
	var tr := Vector2(rect.end.x, rect.position.y)
	var bl := Vector2(rect.position.x, rect.end.y)
	var br := rect.end

	selection_pad.draw_line(tl, tl + Vector2(c_len, 0), Color.WHITE, 4.0)
	selection_pad.draw_line(tl, tl + Vector2(0, c_len), Color.WHITE, 4.0)
	selection_pad.draw_line(tr, tr + Vector2(-c_len, 0), Color.WHITE, 4.0)
	selection_pad.draw_line(tr, tr + Vector2(0, c_len), Color.WHITE, 4.0)
	selection_pad.draw_line(bl, bl + Vector2(c_len, 0), Color.WHITE, 4.0)
	selection_pad.draw_line(bl, bl + Vector2(0, -c_len), Color.WHITE, 4.0)
	selection_pad.draw_line(br, br + Vector2(-c_len, 0), Color.WHITE, 4.0)
	selection_pad.draw_line(br, br + Vector2(0, -c_len), Color.WHITE, 4.0)

func _draw_facility_hold_ring() -> void:
	if facility_hold_progress <= 0.01:
		return
	var radius := 30.0
	var center := Vector2(0, -45)
	var bg_col := Color(0.08, 0.1, 0.14, 0.65)
	var fg_col := Color(0.35, 0.95, 1.0, 0.95).lerp(Color(0.4, 1.0, 0.45, 1.0), facility_hold_progress)
	facility_hold_ring.draw_circle(center, radius + 3.0, bg_col)
	var start_angle := -PI * 0.5
	var end_angle := start_angle + TAU * clampf(facility_hold_progress, 0.0, 1.0)
	facility_hold_ring.draw_arc(center, radius, start_angle, end_angle, 32, fg_col, 5.0, true)

func _draw_path_cursor() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(CELL_SIZE, CELL_SIZE))
	if current_tool == ToolMode.DRAW:
		path_cursor.draw_rect(rect, Color(0.95, 0.8, 0.3, 0.35), true)
		path_cursor.draw_rect(rect, Color(1.0, 0.9, 0.4, 0.95), false, 2.5)
	elif current_tool == ToolMode.ERASE:
		path_cursor.draw_rect(rect, Color(0.95, 0.25, 0.25, 0.35), true)
		path_cursor.draw_rect(rect, Color(1.0, 0.35, 0.35, 0.95), false, 2.5)

func _prepare_facilities_for_editing() -> void:
	if not is_instance_valid(facilities_container):
		return
	for child in facilities_container.get_children():
		if child is Facility:
			child.set_process(false)
			if is_instance_valid(child.name_label):
				child.name_label.visible = false
			if is_instance_valid(child.status_label):
				child.status_label.visible = false

# =============================================================================
# On-Map Land Expansion Signs (Click to Open Tick/Cross, Auto-Close on Mouse Leave)
# =============================================================================

func _build_land_sale_signs() -> void:
	land_signs_root = Node2D.new()
	land_signs_root.name = "LandSaleSignsRoot"
	land_signs_root.z_index = 35
	add_child(land_signs_root)

	var sign_defs := {
		2: {"pos": Vector2(240, 176), "title": "RIGHT BOTTOM"},
		3: {"pos": Vector2(-240, -192), "title": "LEFT TOP"},
		4: {"pos": Vector2(240, -192), "title": "RIGHT TOP"},
	}

	var sign_atlas := UIPack.make_region_atlas(UIPack.WOOD_SIGN_REGION)

	for q_idx in sign_defs.keys():
		var info: Dictionary = sign_defs[q_idx]
		var sign_node := Node2D.new()
		sign_node.name = "LandSign_Q%d" % q_idx
		sign_node.position = info["pos"]
		land_signs_root.add_child(sign_node)

		# Clickable Wooden Sign Button
		var sign_btn := TextureButton.new()
		sign_btn.name = "SignButton"
		sign_btn.texture_normal = sign_atlas
		sign_btn.texture_hover = sign_atlas
		sign_btn.texture_pressed = sign_atlas
		sign_btn.ignore_texture_size = true
		sign_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		sign_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sign_btn.custom_minimum_size = Vector2(96, 112)
		sign_btn.size = Vector2(96, 112)
		sign_btn.position = Vector2(-48, -56)
		sign_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sign_btn.tooltip_text = "Click to buy %s" % info["title"]
		sign_btn.pressed.connect(_on_land_sign_clicked.bind(q_idx))
		sign_node.add_child(sign_btn)

		# Upper Plank Text ("FOR SALE")
		var sale_lbl := Label.new()
		sale_lbl.text = "SALE"
		sale_lbl.position = Vector2(-44, -48)
		sale_lbl.size = Vector2(88, 28)
		sale_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sale_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sale_lbl.add_theme_font_size_override("font_size", 18)
		sale_lbl.add_theme_color_override("font_color", Color(0.24, 0.13, 0.05))
		sale_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sign_node.add_child(sale_lbl)

		# Lower Plank Price Text ("$100") — overlaying the bottom sign plank
		var price_lbl := Label.new()
		price_lbl.name = "PriceLabel"
		price_lbl.text = "$100"
		price_lbl.position = Vector2(-44, 20)
		price_lbl.size = Vector2(88, 26)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_lbl.add_theme_font_size_override("font_size", 20)
		price_lbl.add_theme_color_override("font_color", Color(0.14, 0.42, 0.14))
		price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sign_node.add_child(price_lbl)

		# Confirmation Popup ([✓] [✕]) — Hidden until sign is clicked, auto-closes on mouse away
		var confirm_box := PanelContainer.new()
		confirm_box.name = "ConfirmBox"
		confirm_box.visible = false
		confirm_box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		UIPack.style_panel(confirm_box, "wood_frame_dark", Vector4(8, 6, 8, 6))
		confirm_box.position = Vector2(-50, -106)
		sign_node.add_child(confirm_box)

		var hbox := HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 10)
		confirm_box.add_child(hbox)

		var btn_yes := _make_icon_button(
			"ConfirmBuyLand_Q%d" % q_idx,
			tex_tick_normal,
			tex_tick_pressed,
			Vector2(34, 34),
			"Confirm Land Purchase (✓)"
		)
		btn_yes.pressed.connect(_on_confirm_buy_land_quarter.bind(q_idx))
		hbox.add_child(btn_yes)

		var btn_no := _make_icon_button(
			"CancelBuyLand_Q%d" % q_idx,
			tex_cross_normal,
			tex_cross_pressed,
			Vector2(34, 34),
			"Cancel (✕)"
		)
		btn_no.pressed.connect(_close_land_sign_confirmations)
		hbox.add_child(btn_no)

		land_signs[q_idx] = {
			"node": sign_node,
			"price_label": price_lbl,
			"confirm_box": confirm_box,
		}

	_refresh_land_signs()

func update_text_zoom(zoom_val: float) -> void:
	var s: float = clampf(1.0 / zoom_val, 0.55, 1.6)
	var scale_vec := Vector2(s, s)
	for q_idx in land_signs.keys():
		var data: Dictionary = land_signs[q_idx]
		var s_node: Node2D = data.get("node")
		var p_lbl: Label = data.get("price_label")
		if is_instance_valid(p_lbl):
			p_lbl.pivot_offset = p_lbl.size * 0.5
			p_lbl.scale = scale_vec
		if is_instance_valid(s_node):
			var sale_l: Label = s_node.get_node_or_null("Label")
			if is_instance_valid(sale_l):
				sale_l.pivot_offset = sale_l.size * 0.5
				sale_l.scale = scale_vec
	if is_instance_valid(floating_combo_label):
		floating_combo_label.pivot_offset = floating_combo_label.size * 0.5
		floating_combo_label.scale = scale_vec

func _refresh_land_signs() -> void:
	var next_cost: int = GameManager.get_next_quarter_cost()
	for q_idx in land_signs.keys():
		var data: Dictionary = land_signs[q_idx]
		var sign_node: Node2D = data["node"]
		var price_lbl: Label = data["price_label"]
		var confirm_box: Control = data["confirm_box"]
		var unlocked: bool = GameManager.is_quarter_unlocked(q_idx)
		sign_node.visible = not unlocked
		if unlocked and active_confirm_quarter == q_idx:
			active_confirm_quarter = 0
		confirm_box.visible = (active_confirm_quarter == q_idx and not unlocked)
		price_lbl.text = "$%d" % next_cost
	if is_instance_valid(land_grid_overlay):
		land_grid_overlay.queue_redraw()

func _on_land_sign_clicked(q_idx: int) -> void:
	if GameManager.is_quarter_unlocked(q_idx):
		return
	var next_q: int = GameManager.get_next_locked_quarter()
	if q_idx != next_q:
		_show_status_toast("⚠ Must buy %s first!" % GameManager.QUARTER_NAMES[next_q - 1], Color(1.0, 0.45, 0.45))
		return
	active_confirm_quarter = q_idx
	_refresh_land_signs()
	var cost: int = GameManager.get_next_quarter_cost()
	_show_status_toast("Buy %s for $%d? Click ✓ to confirm." % [GameManager.QUARTER_NAMES[q_idx - 1], cost], Color(1.0, 0.9, 0.45))

func _close_land_sign_confirmations() -> void:
	if active_confirm_quarter != 0:
		active_confirm_quarter = 0
		_refresh_land_signs()

func _on_confirm_buy_land_quarter(q_idx: int) -> void:
	if GameManager.is_quarter_unlocked(q_idx):
		_close_land_sign_confirmations()
		return
	var cost: int = GameManager.get_next_quarter_cost()
	if GameManager.money < cost:
		_show_status_toast("⚠ Not enough money! Need $%d (Have $%d)" % [cost, GameManager.money], Color(1.0, 0.4, 0.4))
		_close_land_sign_confirmations()
		return

	GameManager.money -= cost
	GameManager.unlock_quarter(q_idx)
	active_confirm_quarter = 0

	if is_instance_valid(phase2_root):
		phase2_root.rebuild_grass_tilemap()
	_refresh_land_signs()
	_refresh_money_and_counts()
	_show_status_toast("✓ Purchased %s (-$%d)!" % [GameManager.QUARTER_NAMES[q_idx - 1], cost], Color(0.45, 1.0, 0.58))

# =============================================================================
# Editor UI: Left Panel + Hover Description Panel (Matching Reference Image)
# =============================================================================

func _build_editor_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "EditorUILayer"
	ui_layer.layer = 20
	add_child(ui_layer)

	# -------------------------------------------------------------------------
	# 1. Left Docked Panel (Matches Reference Image)
	# -------------------------------------------------------------------------
	left_panel = PanelContainer.new()
	left_panel.name = "LeftEditorPanel"
	left_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	left_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_panel.position = Vector2(14, 14)
	left_panel.custom_minimum_size = Vector2(416, 860)
	UIPack.style_panel(left_panel, "wood_frame_dark", Vector4(16, 14, 16, 16))
	ui_layer.add_child(left_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	left_panel.add_child(vb)

	# Header Title
	var title_lbl := Label.new()
	title_lbl.text = "★ FACILITY SHOP & LAYOUT"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	vb.add_child(title_lbl)

	# Balance Row: [Coin Icon] [1500] [-50]
	var balance_row := HBoxContainer.new()
	balance_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	balance_row.add_theme_constant_override("separation", 12)
	vb.add_child(balance_row)

	var coin_icon := TextureRect.new()
	coin_icon.texture = UIPack.make_region_atlas(UIPack.COIN_REGION)
	coin_icon.custom_minimum_size = Vector2(36, 44)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	balance_row.add_child(coin_icon)

	balance_label = Label.new()
	balance_label.name = "BalanceLabel"
	balance_label.text = "%d" % GameManager.money
	balance_label.add_theme_font_size_override("font_size", 36)
	balance_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	balance_row.add_child(balance_label)

	pending_cost_label = Label.new()
	pending_cost_label.name = "PendingCostLabel"
	pending_cost_label.text = "-50"
	pending_cost_label.visible = false
	pending_cost_label.add_theme_font_size_override("font_size", 32)
	pending_cost_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	balance_row.add_child(pending_cost_label)

	# Status Toast Feedback Label
	status_toast_label = Label.new()
	status_toast_label.text = ""
	status_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_toast_label.add_theme_font_size_override("font_size", 18)
	status_toast_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	status_toast_label.visible = false
	vb.add_child(status_toast_label)

	vb.add_child(_make_separator())

	# 2. Facilities Section (2-Column Scrollable Grid of Square Beige Cards)
	fac_header_label = Label.new()
	fac_header_label.text = "FACILITIES IN RESORT (3)"
	fac_header_label.add_theme_font_size_override("font_size", 20)
	fac_header_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vb.add_child(fac_header_label)

	var fac_scroll := ScrollContainer.new()
	fac_scroll.custom_minimum_size = Vector2(0, 376)
	fac_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fac_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(fac_scroll)

	var fac_grid := GridContainer.new()
	fac_grid.columns = 2
	fac_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fac_grid.add_theme_constant_override("h_separation", 14)
	fac_grid.add_theme_constant_override("v_separation", 14)
	fac_scroll.add_child(fac_grid)

	_build_facility_grid_cards(fac_grid)

	vb.add_child(_make_separator())

	# 3. Pathway Builder Section ("Draw", "- Erase", "✕ Clear All")
	var path_hdr := Label.new()
	path_hdr.text = "PATHWAY BUILDER"
	path_hdr.add_theme_font_size_override("font_size", 20)
	path_hdr.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vb.add_child(path_hdr)

	var tool_box := HBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 10)
	vb.add_child(tool_box)

	btn_tool_draw = Button.new()
	btn_tool_draw.text = "Draw"
	btn_tool_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tool_draw.custom_minimum_size = Vector2(0, 38)
	btn_tool_draw.focus_mode = Control.FOCUS_NONE
	btn_tool_draw.add_theme_font_size_override("font_size", 20)
	btn_tool_draw.pressed.connect(_on_toggle_tool_mode.bind(ToolMode.DRAW))
	tool_box.add_child(btn_tool_draw)

	btn_tool_erase = Button.new()
	btn_tool_erase.text = "- Erase"
	btn_tool_erase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tool_erase.custom_minimum_size = Vector2(0, 38)
	btn_tool_erase.focus_mode = Control.FOCUS_NONE
	btn_tool_erase.add_theme_font_size_override("font_size", 20)
	btn_tool_erase.pressed.connect(_on_toggle_tool_mode.bind(ToolMode.ERASE))
	tool_box.add_child(btn_tool_erase)

	var btn_clear := Button.new()
	btn_clear.text = "✕ Clear All"
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.custom_minimum_size = Vector2(0, 38)
	btn_clear.focus_mode = Control.FOCUS_NONE
	btn_clear.add_theme_font_size_override("font_size", 20)
	UIPack.style_button(btn_clear, Color(1.0, 0.78, 0.68))
	btn_clear.pressed.connect(_clear_all_pathways)
	vb.add_child(btn_clear)

	path_count_label = Label.new()
	path_count_label.add_theme_font_size_override("font_size", 18)
	path_count_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	vb.add_child(path_count_label)
	_refresh_path_count()

	vb.add_child(_make_separator())

	# 4. Save & Cancel Actions
	var btn_save := Button.new()
	btn_save.text = "✓ Save & Return to Desk"
	btn_save.focus_mode = Control.FOCUS_NONE
	btn_save.custom_minimum_size = Vector2(0, 44)
	btn_save.add_theme_font_size_override("font_size", 20)
	UIPack.style_button(btn_save, Color(0.75, 1.0, 0.78))
	btn_save.pressed.connect(_on_save_and_exit)
	vb.add_child(btn_save)

	var btn_cancel := Button.new()
	btn_cancel.text = "✕ Cancel & Return"
	btn_cancel.focus_mode = Control.FOCUS_NONE
	btn_cancel.custom_minimum_size = Vector2(0, 40)
	btn_cancel.add_theme_font_size_override("font_size", 20)
	UIPack.style_button(btn_cancel, Color(1.0, 0.78, 0.72))
	btn_cancel.pressed.connect(_on_cancel_and_exit)
	vb.add_child(btn_cancel)

	# -------------------------------------------------------------------------
	# 5. Hover Description Side Panel (Attached to Right of Left Panel)
	# -------------------------------------------------------------------------
	_build_hover_description_panel()
	_update_tool_buttons()

func _build_hover_description_panel() -> void:
	hover_desc_panel = PanelContainer.new()
	hover_desc_panel.name = "HoverDescriptionPanel"
	hover_desc_panel.visible = false
	hover_desc_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hover_desc_panel.position = Vector2(432, 14)
	hover_desc_panel.custom_minimum_size = Vector2(310, 460)
	hover_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIPack.style_panel(hover_desc_panel, "wood_frame_dark", Vector4(22, 20, 22, 22))
	ui_layer.add_child(hover_desc_panel)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.add_theme_constant_override("separation", 14)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_desc_panel.add_child(vb)

	# Building Picture at Top
	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(icon_center)

	hover_icon_rect = TextureRect.new()
	hover_icon_rect.custom_minimum_size = Vector2(124, 124)
	hover_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hover_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hover_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hover_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(hover_icon_rect)

	# Facility Name
	hover_name_label = Label.new()
	hover_name_label.text = "Facility Name"
	hover_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_name_label.add_theme_font_size_override("font_size", 24)
	hover_name_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	hover_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hover_name_label.add_theme_constant_override("outline_size", 4)
	vb.add_child(hover_name_label)

	# Description (Payout & Cost)
	hover_desc_label = Label.new()
	hover_desc_label.text = "Description"
	hover_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_desc_label.add_theme_font_size_override("font_size", 18)
	hover_desc_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	vb.add_child(hover_desc_label)

	vb.add_child(_make_separator())

	# Combo Skill Title & Description
	hover_combo_title_label = Label.new()
	hover_combo_title_label.text = "Combo Skill"
	hover_combo_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_combo_title_label.add_theme_font_size_override("font_size", 20)
	hover_combo_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(hover_combo_title_label)

	hover_combo_desc_label = Label.new()
	hover_combo_desc_label.text = ""
	hover_combo_desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_combo_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_combo_desc_label.add_theme_font_size_override("font_size", 18)
	hover_combo_desc_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.98))
	vb.add_child(hover_combo_desc_label)

	vb.add_child(_make_separator())

	# Flavor Text
	hover_flavor_label = Label.new()
	hover_flavor_label.text = "Flavor text"
	hover_flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_flavor_label.add_theme_font_size_override("font_size", 16)
	hover_flavor_label.add_theme_color_override("font_color", Color(0.8, 0.74, 0.86))
	vb.add_child(hover_flavor_label)

func _build_facility_grid_cards(grid: GridContainer) -> void:
	for fac_id in GameManager.SHOP_FACILITY_ORDER:
		var tmpl: Dictionary = GameManager.FACILITY_TEMPLATES.get(fac_id, {})
		if tmpl.is_empty():
			continue

		var card := PanelContainer.new()
		card.name = "Card_" + fac_id
		card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.custom_minimum_size = Vector2(178, 174)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIPack.style_panel(card, "beige_raised", Vector4(10, 10, 10, 10))
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_facility_card_gui_input.bind(fac_id))
		card.mouse_entered.connect(_on_facility_card_hover_entered.bind(fac_id))
		card.mouse_exited.connect(_on_facility_card_hover_exited.bind(fac_id))
		grid.add_child(card)

		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 4)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vb)

		# 1. Facility Name
		var name_lbl := Label.new()
		name_lbl.text = tmpl.get("display_name", fac_id.capitalize())
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.18, 0.1, 0.04))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_lbl)

		# 2. Building Thumbnail Sprite
		var icon_center := CenterContainer.new()
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(icon_center)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(68, 68)
		icon_rect.texture = _make_building_atlas(
			tmpl.get("sheet_path", "res://assets/PhaseII_Map/Buildings1.png"),
			int(tmpl.get("building_row", 0))
		)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_center.add_child(icon_rect)

		# 3. Price Label ("$50")
		var price_lbl := Label.new()
		price_lbl.text = "$%d" % int(tmpl.get("cost", 50))
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_lbl.add_theme_font_size_override("font_size", 18)
		price_lbl.add_theme_color_override("font_color", Color(0.22, 0.14, 0.06))
		price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(price_lbl)

		# 4. Owned Storage Count ("Owned : 0" or "Day X 🔒")
		var owned_lbl := Label.new()
		owned_lbl.text = "Owned : 0"
		owned_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owned_lbl.add_theme_font_size_override("font_size", 18)
		owned_lbl.add_theme_color_override("font_color", Color(0.24, 0.15, 0.07))
		owned_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(owned_lbl)

		facility_cards[fac_id] = {
			"card": card,
			"name_lbl": name_lbl,
			"icon_rect": icon_rect,
			"price_lbl": price_lbl,
			"owned_lbl": owned_lbl,
		}

func _on_facility_card_hover_entered(fac_id: String) -> void:
	hovered_card_fac_id = fac_id
	var tmpl: Dictionary = GameManager.FACILITY_TEMPLATES.get(fac_id, {})
	if tmpl.is_empty() or not is_instance_valid(hover_desc_panel):
		return

	hover_icon_rect.texture = _make_building_atlas(
		tmpl.get("sheet_path", "res://assets/PhaseII_Map/Buildings1.png"),
		int(tmpl.get("building_row", 0))
	)
	var unlocked := GameManager.is_facility_unlocked(fac_id)
	var unlock_d: int = int(tmpl.get("unlock_day", 1))
	hover_name_label.text = tmpl.get("display_name", fac_id.capitalize())
	if not unlocked:
		hover_name_label.text += " (Unlocks Day %d)" % unlock_d
	hover_desc_label.text = tmpl.get("description", "")
	hover_combo_title_label.text = tmpl.get("combo_title", "Combo Skill")
	hover_combo_desc_label.text = tmpl.get("combo_desc", "")
	hover_flavor_label.text = tmpl.get("flavor_text", "")
	hover_desc_panel.visible = true

func _on_facility_card_hover_exited(fac_id: String) -> void:
	if hovered_card_fac_id == fac_id:
		hovered_card_fac_id = ""
		if is_instance_valid(hover_desc_panel):
			hover_desc_panel.visible = false

func _on_facility_card_gui_input(event: InputEvent, fac_id: String) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	var tmpl: Dictionary = GameManager.FACILITY_TEMPLATES.get(fac_id, {})
	if tmpl.is_empty():
		return

	# 1. Check Day Unlock Gate
	if not GameManager.is_facility_unlocked(fac_id):
		var unlock_d: int = int(tmpl.get("unlock_day", 1))
		_show_status_toast("🔒 %s unlocks on Day %d!" % [tmpl.get("display_name", "Facility"), unlock_d], Color(1.0, 0.65, 0.35))
		return

	# Switch back to MOVE mode if in DRAW/ERASE
	if current_tool != ToolMode.MOVE:
		current_tool = ToolMode.MOVE
		_update_tool_buttons()

	# If another facility is currently being previewed or moved, cancel/confirm it first
	if is_instance_valid(selected_facility):
		if is_pending_purchase_facility or is_pending_stored_placement:
			_on_cancel_facility_placement()
		else:
			_on_confirm_facility_placement()

	var stored_count: int = GameManager.get_stored_facility_count(fac_id)
	var cost: int = GameManager.get_facility_cost(fac_id)
	var spawn_pos := _get_center_spawn_pos(fac_id)
	var new_fac := phase2_root.create_facility_instance(fac_id, spawn_pos)
	new_fac.set_process(false)
	if is_instance_valid(new_fac.name_label):
		new_fac.name_label.visible = false
	if is_instance_valid(new_fac.status_label):
		new_fac.status_label.visible = false

	pending_facility_id = fac_id

	if stored_count > 0:
		# Place from Owned storage (no money cost)
		is_pending_stored_placement = true
		is_pending_purchase_facility = false
		pending_purchase_cost = 0
		_select_and_start_moving(new_fac, false)
	else:
		# Owned is 0: Preview on map and show "-Cost" on the right of the money section
		is_pending_purchase_facility = true
		is_pending_stored_placement = false
		pending_purchase_cost = cost
		_select_and_start_moving(new_fac, false)

	_refresh_money_and_counts()

func _get_center_spawn_pos(fac_id: String = "") -> Vector2:
	var cam_center: Vector2 = phase2_root.camera.position if is_instance_valid(phase2_root) and is_instance_valid(phase2_root.camera) else Vector2(-240, 176)
	var snapped := cam_center.snapped(Vector2(16, 16))
	var dummy_rect := Rect2(-36, -85, 72, 75)
	var test_offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(64, 0),
		Vector2(-64, 0),
		Vector2(0, 64),
		Vector2(0, -64),
		Vector2(64, 64),
		Vector2(-64, 64),
		Vector2(-64, -64),
		Vector2(64, -64),
	]
	for off: Vector2 in test_offsets:
		var p: Vector2 = snapped + off
		if GameManager.is_facility_pos_on_land(p, dummy_rect):
			var overlaps := false
			if is_instance_valid(facilities_container):
				var p_rect := Rect2(p + dummy_rect.position, dummy_rect.size).grow(-4.0)
				for child in facilities_container.get_children():
					if child is Facility and is_instance_valid(child):
						var c_rect := Rect2(child.position + child.get_selection_rect().position, child.get_selection_rect().size).grow(-4.0)
						if p_rect.intersects(c_rect):
							overlaps = true
							break
			if not overlaps:
				return p
	return snapped

func _refresh_money_and_counts() -> void:
	if is_instance_valid(balance_label):
		balance_label.text = "%d" % GameManager.money

	if is_instance_valid(pending_cost_label):
		if is_pending_purchase_facility and pending_purchase_cost > 0:
			pending_cost_label.text = "-%d" % pending_purchase_cost
			pending_cost_label.visible = true
		else:
			pending_cost_label.visible = false

	var map_buildings_count: int = 0
	if is_instance_valid(facilities_container):
		for child in facilities_container.get_children():
			if child is Facility and child.facility_id != "main_building" and child.facility_id != "jail":
				if (is_pending_purchase_facility or is_pending_stored_placement) and child == selected_facility:
					continue
				map_buildings_count += 1

	if is_instance_valid(fac_header_label):
		fac_header_label.text = "FACILITIES IN RESORT (%d)" % map_buildings_count

	for fac_id in facility_cards.keys():
		var ui: Dictionary = facility_cards[fac_id]
		var card: PanelContainer = ui["card"]
		var owned_lbl: Label = ui["owned_lbl"]
		var price_lbl: Label = ui["price_lbl"]
		var tmpl: Dictionary = GameManager.FACILITY_TEMPLATES.get(fac_id, {})
		var unlocked: bool = GameManager.is_facility_unlocked(fac_id)
		var unlock_d: int = int(tmpl.get("unlock_day", 1))
		var stored: int = GameManager.get_stored_facility_count(fac_id)

		price_lbl.text = "$%d" % int(tmpl.get("cost", 50))
		if unlocked:
			card.modulate = Color.WHITE
			owned_lbl.text = "Owned : %d" % stored
			owned_lbl.add_theme_color_override("font_color", Color(0.14, 0.45, 0.14) if stored > 0 else Color(0.24, 0.15, 0.07))
		else:
			# Greyed out locked facility
			card.modulate = Color(0.52, 0.5, 0.54, 0.88)
			owned_lbl.text = "Day %d 🔒" % unlock_d
			owned_lbl.add_theme_color_override("font_color", Color(0.35, 0.2, 0.15))

func _show_status_toast(msg: String, col: Color) -> void:
	if not is_instance_valid(status_toast_label):
		return
	status_toast_label.text = msg
	status_toast_label.add_theme_color_override("font_color", col)
	status_toast_label.visible = true

func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.45, 0.35, 0.48, 0.65)
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep

func _on_toggle_tool_mode(mode: ToolMode) -> void:
	if current_tool == mode:
		current_tool = ToolMode.MOVE
	else:
		current_tool = mode
	_update_tool_buttons()
	if current_tool != ToolMode.MOVE and is_instance_valid(selected_facility):
		if is_pending_purchase_facility or is_pending_stored_placement:
			_on_cancel_facility_placement()
		else:
			_on_confirm_facility_placement()

func _update_tool_buttons() -> void:
	var active_tint := Color(0.72, 1.0, 0.78)
	var inactive_tint := Color(0.95, 0.9, 0.82)
	if is_instance_valid(btn_tool_draw):
		UIPack.style_button(btn_tool_draw, active_tint if current_tool == ToolMode.DRAW else inactive_tint)
	if is_instance_valid(btn_tool_erase):
		UIPack.style_button(btn_tool_erase, active_tint if current_tool == ToolMode.ERASE else inactive_tint)

# =============================================================================
# Facility Placement, Relocation & Storage Inventory ("Owned : X")
# =============================================================================

func _select_and_start_moving(fac: Facility, start_dragging: bool = true) -> void:
	if selected_facility == fac and is_dragging_facility:
		return

	if is_instance_valid(selected_facility) and selected_facility != fac:
		if is_pending_purchase_facility or is_pending_stored_placement:
			_on_cancel_facility_placement()
		else:
			_on_confirm_facility_placement()

	selected_facility = fac
	original_facility_pos = fac.position
	is_dragging_facility = start_dragging
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
	is_pending_stored_placement = false
	pending_purchase_cost = 0
	_select_and_start_moving(fac, true)
	drag_mouse_offset = fac.position - get_global_mouse_position()
	_refresh_money_and_counts()

	if is_instance_valid(fac.visual_root):
		var squish := create_tween()
		squish.tween_property(fac.visual_root, "scale", Vector2(1.15, 1.15), 0.08)
		squish.tween_property(fac.visual_root, "scale", Vector2(1.0, 1.0), 0.1)

func does_facility_overlap_any(fac: Facility, pos: Vector2) -> bool:
	if not is_instance_valid(fac) or not is_instance_valid(facilities_container):
		return false
	var fac_rect: Rect2 = fac.get_selection_rect() if fac.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
	var my_world_rect := Rect2(pos + fac_rect.position, fac_rect.size).grow(-4.0)
	for other in facilities_container.get_children():
		if other is Facility and other != fac and is_instance_valid(other):
			if (is_pending_purchase_facility or is_pending_stored_placement) and other == selected_facility:
				continue
			var other_rect: Rect2 = other.get_selection_rect() if other.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
			var other_world_rect := Rect2(other.position + other_rect.position, other_rect.size).grow(-4.0)
			if my_world_rect.intersects(other_world_rect):
				return true
	return false

func is_facility_placement_valid(fac: Facility, pos: Vector2) -> bool:
	if not is_instance_valid(fac):
		return false
	var fac_rect: Rect2 = fac.get_selection_rect() if fac.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
	if not GameManager.is_facility_pos_on_land(pos, fac_rect):
		return false
	if does_facility_overlap_any(fac, pos):
		return false
	return true

func _on_confirm_facility_placement() -> void:
	if not is_instance_valid(selected_facility):
		return

	var fac_rect: Rect2 = selected_facility.get_selection_rect() if selected_facility.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
	if not GameManager.is_facility_pos_on_land(selected_facility.position, fac_rect):
		_show_status_toast("⚠ Must place entirely on owned grass land!", Color(1.0, 0.4, 0.4))
		return

	if does_facility_overlap_any(selected_facility, selected_facility.position):
		_show_status_toast("⚠ Cannot place here! Facility overlaps another building.", Color(1.0, 0.4, 0.4))
		return

	if is_pending_purchase_facility:
		if GameManager.money < pending_purchase_cost:
			_show_status_toast("⚠ Not enough money! Need $%d (Have $%d)" % [pending_purchase_cost, GameManager.money], Color(1.0, 0.4, 0.4))
			return
		GameManager.money -= pending_purchase_cost
		is_pending_purchase_facility = false
		pending_purchase_cost = 0
	elif is_pending_stored_placement:
		GameManager.add_stored_facility(selected_facility.facility_id, -1)
		is_pending_stored_placement = false

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

	if is_pending_purchase_facility or is_pending_stored_placement:
		var to_remove := selected_facility
		selected_facility = null
		is_dragging_facility = false
		is_pending_purchase_facility = false
		is_pending_stored_placement = false
		pending_purchase_cost = 0
		_hide_selection_visuals()
		if is_instance_valid(facilities_container):
			facilities_container.remove_child(to_remove)
		to_remove.queue_free()
		_refresh_money_and_counts()
		return

	var t := create_tween()
	t.tween_property(selected_facility, "position", original_facility_pos, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	selected_facility.z_index = 0
	selected_facility = null
	is_dragging_facility = false
	_hide_selection_visuals()
	_refresh_money_and_counts()

func _on_store_selected_facility() -> void:
	if not is_instance_valid(selected_facility):
		return

	if is_pending_purchase_facility or is_pending_stored_placement:
		_on_cancel_facility_placement()
		return

	var fac_id: String = selected_facility.facility_id
	if fac_id == "main_building" or fac_id == "jail":
		_show_status_toast("⚠ %s must remain in the resort!" % selected_facility.display_name, Color(1.0, 0.55, 0.35))
		return

	var fac_name := selected_facility.display_name
	var to_remove := selected_facility
	selected_facility = null
	is_dragging_facility = false
	_hide_selection_visuals()

	if is_instance_valid(facilities_container):
		facilities_container.remove_child(to_remove)
	to_remove.queue_free()

	# Facility cannot be sold — removing it from the map returns it to Owned storage (+1)
	GameManager.add_stored_facility(fac_id, 1)
	_sync_facilities_to_game_manager()
	_refresh_money_and_counts()
	_show_status_toast("Stored %s (Owned : %d)." % [fac_name, GameManager.get_stored_facility_count(fac_id)], Color(0.55, 0.9, 1.0))

func _update_selection_visuals() -> void:
	if not is_instance_valid(selected_facility):
		_hide_selection_visuals()
		return

	selection_pad.visible = true
	selection_pad.global_position = selected_facility.global_position
	selection_pad.queue_redraw()

	# Update live Combo Skill delta label above the selected building
	if is_instance_valid(floating_combo_label):
		var fac_id: String = selected_facility.facility_id
		if fac_id != "main_building" and fac_id != "jail":
			var all_facs: Array = facilities_container.get_children() if is_instance_valid(facilities_container) else []
			var combo_res: Dictionary = GameManager.calculate_facility_combo(
				fac_id,
				selected_facility.position,
				all_facs,
				selected_facility
			)
			var bonus: int = int(combo_res.get("bonus", 0))
			if bonus > 0:
				floating_combo_label.text = "Combo Bonus: +$%d / visit" % bonus
				floating_combo_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5))
				floating_combo_label.visible = true
			elif bonus < 0:
				floating_combo_label.text = "Combo Penalty: -$%d / visit" % abs(bonus)
				floating_combo_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.38))
				floating_combo_label.visible = true
			else:
				floating_combo_label.visible = false
		else:
			floating_combo_label.visible = false

	# Show minus (store) button only for already-placed removable facilities
	if is_instance_valid(floating_btn_minus):
		var is_removable_existing := (
			not is_pending_purchase_facility
			and not is_pending_stored_placement
			and selected_facility.facility_id != "main_building"
			and selected_facility.facility_id != "jail"
		)
		floating_btn_minus.visible = is_removable_existing

	var fac_rect: Rect2 = selected_facility.get_selection_rect() if selected_facility.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
	floating_widget.visible = true
	floating_widget.global_position = selected_facility.global_position + Vector2(0, fac_rect.position.y - 12.0)

	var is_valid := is_facility_placement_valid(selected_facility, selected_facility.position)
	if is_instance_valid(floating_btn_tick):
		floating_btn_tick.modulate = Color.WHITE if is_valid else Color(1.0, 0.45, 0.45, 0.65)

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
			if (is_pending_purchase_facility or is_pending_stored_placement) and child == selected_facility:
				continue
			fac_dict[child.name] = child.position
			fac_dict[child.facility_id] = child.position
			var tmpl: Dictionary = GameManager.FACILITY_TEMPLATES.get(child.facility_id, {})
			fac_list.append({
				"name": child.name,
				"facility_id": child.facility_id,
				"display_name": child.display_name,
				"position": child.position,
				"sheet_path": tmpl.get("sheet_path", "res://assets/PhaseII_Map/Buildings1.png"),
				"building_row": child.building_row,
				"base_cycle_time": child.base_cycle_time,
				"base_payout": child.base_payout,
			})
	GameManager.resort_layout["facilities"] = fac_dict
	GameManager.resort_layout["facility_instances"] = fac_list

# =============================================================================
# Input Processing: Facility Dragging, Sign Auto-Close & Pathway Painting
# =============================================================================

func _process(delta: float) -> void:
	if not visible:
		return

	var mouse_world := get_global_mouse_position()

	# 1. Auto-close Land Sale Sign confirmation if mouse moves away
	if active_confirm_quarter > 0 and land_signs.has(active_confirm_quarter):
		var s_node: Node2D = land_signs[active_confirm_quarter]["node"]
		if is_instance_valid(s_node):
			var sign_center := s_node.global_position + Vector2(0, -35)
			if mouse_world.distance_to(sign_center) > SIGN_AUTO_CLOSE_RADIUS:
				_close_land_sign_confirmations()

	# 2. Update hold-to-lift charge
	_handle_facility_hold(delta)

	# 3. Update dragged facility position
	if is_dragging_facility and is_instance_valid(selected_facility):
		selected_facility.position = (mouse_world + drag_mouse_offset).snapped(Vector2(16, 16))
		_update_selection_visuals()

	# 4. Update path cursor in Draw / Erase mode
	if current_tool == ToolMode.DRAW or current_tool == ToolMode.ERASE:
		var cell := GameManager.world_to_path_cell(mouse_world)
		path_cursor.visible = true
		path_cursor.global_position = Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
		path_cursor.queue_redraw()
	else:
		path_cursor.visible = false

	# 5. Update facility hover label on map
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
			# If a facility is currently selected and the player clicks it, drag immediately
			var clicked_fac := _get_facility_at_point(mouse_world)
			if clicked_fac and selected_facility == clicked_fac:
				is_dragging_facility = true
				drag_mouse_offset = clicked_fac.position - mouse_world
				get_viewport().set_input_as_handled()
				return

			if current_tool == ToolMode.DRAW:
				_paint_path_tile(mouse_world)
				get_viewport().set_input_as_handled()
				return
			elif current_tool == ToolMode.ERASE:
				_erase_path_tile(mouse_world)
				get_viewport().set_input_as_handled()
				return

			if clicked_fac:
				hold_target_facility = clicked_fac
				is_holding_facility = true
				facility_hold_progress = 0.25
				facility_hold_ring.global_position = clicked_fac.global_position
				facility_hold_ring.visible = true
				facility_hold_ring.queue_redraw()
				get_viewport().set_input_as_handled()
				return

		else:
			if is_holding_facility:
				is_holding_facility = false
			if is_dragging_facility:
				is_dragging_facility = false
				_update_selection_visuals()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_world := get_global_mouse_position()
		if current_tool == ToolMode.DRAW:
			_paint_path_tile(mouse_world)
		elif current_tool == ToolMode.ERASE:
			_erase_path_tile(mouse_world)

func _get_facility_at_point(point: Vector2) -> Facility:
	if not is_instance_valid(facilities_container):
		return null
	var candidates: Array[Facility] = []
	for child in facilities_container.get_children():
		if child is Facility and is_instance_valid(child) and child.is_point_inside(point):
			candidates.append(child)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	# Multiple candidates contain point (e.g. adjacent/overlapping):
	# Pick the one whose visual center is closest to click point, tiebreak with frontmost Y
	candidates.sort_custom(func(a: Facility, b: Facility) -> bool:
		var rect_a: Rect2 = a.get_selection_rect() if a.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
		var rect_b: Rect2 = b.get_selection_rect() if b.has_method("get_selection_rect") else Rect2(-45, -90, 90, 85)
		var center_a: Vector2 = a.global_position + rect_a.get_center()
		var center_b: Vector2 = b.global_position + rect_b.get_center()
		var dist_a: float = point.distance_squared_to(center_a)
		var dist_b: float = point.distance_squared_to(center_b)
		if absf(dist_a - dist_b) > 36.0:
			return dist_a < dist_b
		return a.global_position.y > b.global_position.y
	)
	return candidates[0]

# =============================================================================
# Pathway Operations
# =============================================================================

func _paint_path_tile(world_pos: Vector2) -> void:
	var cell := GameManager.world_to_path_cell(world_pos)
	if not GameManager.is_land_cell_unlocked(cell):
		_show_status_toast("⚠ Unlock this land quarter first via its For Sale sign!", Color(1.0, 0.4, 0.4))
		return
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

func _refresh_path_count() -> void:
	if is_instance_valid(path_count_label):
		var count: int = GameManager.path_cell_lookup.size()
		path_count_label.text = "Path Tiles Placed: %d" % count

# =============================================================================
# Save & Exit Operations
# =============================================================================

func _on_save_and_exit() -> void:
	if is_instance_valid(selected_facility):
		if is_pending_purchase_facility or is_pending_stored_placement:
			_on_cancel_facility_placement()
		else:
			if not is_facility_placement_valid(selected_facility, selected_facility.position):
				selected_facility.position = original_facility_pos
			_on_confirm_facility_placement()

	_sync_facilities_to_game_manager()

	layout_saved.emit()
	GameManager.is_layout_edit_mode = false
	GameManager.returned_from_layout_editor = true
	GameManager.change_scene("res://scene/front_desk.tscn")

func _on_cancel_and_exit() -> void:
	GameManager.money = initial_money
	GameManager.resort_layout = initial_layout_snapshot.duplicate(true)
	GameManager.path_cell_lookup.clear()
	for cell in GameManager.resort_layout.get("pathways", []):
		if cell is Vector2i:
			GameManager.path_cell_lookup[cell] = true
	GameManager.land_cell_lookup.clear()
	for cell in GameManager.resort_layout.get("land_cells", []):
		if cell is Vector2i:
			GameManager.land_cell_lookup[cell] = true

	layout_cancelled.emit()
	GameManager.is_layout_edit_mode = false
	GameManager.returned_from_layout_editor = true
	GameManager.change_scene("res://scene/front_desk.tscn")
