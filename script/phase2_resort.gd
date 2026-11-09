class_name Phase2Resort
extends Node2D
## Phase 2: Resort / Pasture Manager.
## Manages the 60s Rush Hour, guest pathfinding to facilities, active micro-events,
## rapid repairs, wolf deportation, and the end-of-rush ledger.

const RUSH_HOUR_DURATION: float = 60.0
const NO_WOLF_SPAWN_CUTOFF: float = 15.0
const FREEZE_BOMB_RADIUS: float = 115.0
const FREEZE_BOMB_DURATION: float = 5.0
const GUEST_SCENE := preload("res://scene/resort_guest.tscn")
const BUBBLE_SCENE := preload("res://scene/tip_bubble.tscn")
const FACILITY_SCENE := preload("res://scene/facility.tscn")
const RESORT_LAYOUT_EDITOR := preload("res://script/resort_layout_editor.gd")

var time_left: float = RUSH_HOUR_DURATION
var is_active: bool = false
var resort_revenue: int = 0
var resort_tips: int = 0
var resort_damages: int = 0
var wolves_caught: int = 0
var innocents_jailed: int = 0
var sneak_in_wolves_spawned: int = 0
var spawn_interval: float = 1.6

var guest_queue: Array = []
var active_guests: Array = []
var facilities: Array = []
var layout_editor: Node2D = null

var is_tutorial_active: bool = false

# Node references
@onready var camera: Camera2D = $ResortCamera
@onready var entrance_marker: Marker2D = $WorldRoot/EntranceMarker
@onready var guests_container: Node2D = $WorldRoot/GuestsContainer
@onready var bubbles_container: Node2D = $WorldRoot/BubblesContainer
@onready var facilities_container: Node2D = $WorldRoot/FacilitiesContainer

# UI references
@onready var hud_timer_label: Label = $UILayer/TopHUD/HBoxContainer/TimerLabel
@onready var hud_money_label: Label = $UILayer/TopHUD/HBoxContainer/MoneyLabel
@onready var hud_guests_label: Label = $UILayer/TopHUD/HBoxContainer/GuestsLabel
@onready var hud_wolves_label: Label = $UILayer/TopHUD/HBoxContainer/WolvesLabel
@onready var ledger_panel: PanelContainer = $UILayer/LedgerPanel
@onready var ledger_text: RichTextLabel = $UILayer/LedgerPanel/VBoxContainer/LedgerText
@onready var next_day_button: Button = $UILayer/LedgerPanel/VBoxContainer/NextDayButton

var toggle_names_button: Button = null
var speed_toggle_button: Button = null
var freeze_bomb_button: Button = null
var freeze_aim_indicator: Node2D = null
var is_double_speed: bool = false

func _ready() -> void:
	SfxManager.stop_sfx("phase1theme")
	SfxManager.play_sfx("phase2theme", "Music")
	Engine.time_scale = 1.0
	GameManager.is_aiming_freeze_bomb = false
	ledger_panel.visible = false
	next_day_button.pressed.connect(_on_next_day_pressed)

	if camera.has_signal("zoom_changed"):
		camera.zoom_changed.connect(_on_camera_zoom_changed)

	_setup_toggle_names_button()
	_setup_special_upgrade_controls()

	# Apply custom resort layout, unlocked grass land, and pathways
	_apply_resort_layout()
	rebuild_grass_tilemap()
	var pathways := _setup_pathways()

	# Check if launched in Layout Architect / Edit Mode from Front Desk
	if GameManager.is_layout_edit_mode:
		_init_layout_edit_mode(pathways)
		return

	# Collect all facilities in container for regular rush hour
	for child in facilities_container.get_children():
		if child is Facility:
			facilities.append(child)
			child.payout_earned.connect(_on_payout_earned)
			child.facility_broken.connect(_on_facility_broken)
			child.tip_bubble_requested.connect(_on_tip_bubble_requested)
			if child.has_signal("innocent_jailed"):
				child.innocent_jailed.connect(_on_innocent_jailed)

	GameManager.rebuild_resort_navigation_cache(facilities_container.get_children())

	# Prepare guest pool (including Long Visit stayover sheep from previous round)
	if GameManager.admitted_guests.is_empty():
		#_generate_fallback_pool()
		var max_stay: int = GameManager.get_long_visit_max()
		if max_stay > 0 and not GameManager.stayover_guests.is_empty():
			var count: int = mini(max_stay, GameManager.stayover_guests.size())
			for i in range(count):
				guest_queue.push_front(GameManager.stayover_guests[i].duplicate(true))
			GameManager.last_stayover_count = count
		else:
			GameManager.last_stayover_count = 0
	else:
		guest_queue = GameManager.build_phase2_guest_queue()

	_inject_dynamic_wolves()

	time_left = RUSH_HOUR_DURATION
	is_active = false
	_refresh_hud()

	_on_camera_zoom_changed(camera.zoom.x)

	_show_phase2_tutorial()

func _show_phase2_tutorial() -> void:
	while GameManager.is_transitioning:
		await get_tree().process_frame
	is_tutorial_active = true
	# Allow the Ledger UI to work while the game is paused
	ledger_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var tutorial_text: String = "[center][font_size=28][b]WELCOME TO THE RESORT![/b][/font_size][/center]\n\n"

	tutorial_text += "[b]YOUR OBJECTIVE[/b]\n"
	tutorial_text += "Manage your resort during the 60-second Rush Hour. Keep guests happy, earn money, and protect your resort from disguised wolves.\n\n"

	tutorial_text += "[b]1. WATCH YOUR GUESTS[/b]\n"
	tutorial_text += "Guests will enter the resort and visit available facilities. Keep an eye on their behavior and watch for suspicious wolves.\n\n"

	tutorial_text += "[b]2. MANAGE YOUR FACILITIES[/b]\n"
	tutorial_text += "Facilities generate revenue, but some may break down due to wolf's sabotage! Keep your resort running smoothly to avoid damage costs.\n\n"

	tutorial_text += "[b]3. COLLECT TIPS[/b]\n"
	tutorial_text += "Look out for tip bubbles around the resort and collect them for extra income.\n\n"

	tutorial_text += "[b]4. CATCH THE WOLVES[/b]\n"
	tutorial_text += "Wolves disguise themselves as sheep and may sneak into your resort. Identify and deport them before they cause trouble!\n\n"
	
	tutorial_text += "[b]CONTROLS[/b]\n"
	tutorial_text += "WASD or Right-Click to move camera.\nMouse Scroll to Zoom.\nHold Left-Click pick up sheep, release to drop.\n\n"

	tutorial_text += "[center][color=#88ddff]Ready to manage your resort?[/color][/center]"

	ledger_text.text = tutorial_text
	next_day_button.text = "Continue ▶"

	ledger_panel.visible = true
	get_tree().paused = true

func _setup_toggle_names_button() -> void:
	toggle_names_button = Button.new()
	toggle_names_button.name = "ToggleNamesButton"
	toggle_names_button.text = "Name"
	toggle_names_button.custom_minimum_size = Vector2(110, 66)
	toggle_names_button.size = Vector2(110, 66)

	# Position in bottom-right corner of screen (50% larger utility bar)
	toggle_names_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	toggle_names_button.anchor_left = 1.0
	toggle_names_button.anchor_top = 1.0
	toggle_names_button.anchor_right = 1.0
	toggle_names_button.anchor_bottom = 1.0
	toggle_names_button.offset_left = -126.0
	toggle_names_button.offset_top = -82.0
	toggle_names_button.offset_right = -16.0
	toggle_names_button.offset_bottom = -16.0
	toggle_names_button.focus_mode = Control.FOCUS_NONE
	toggle_names_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle_names_button.add_theme_font_size_override("font_size", 21)
	toggle_names_button.tooltip_text = "Toggle Sheep Names On/Off"
	toggle_names_button.pressed.connect(_on_toggle_names_pressed)

	$UILayer.add_child(toggle_names_button)
	_refresh_toggle_names_button()

func _on_toggle_names_pressed() -> void:
	SfxManager.play_sfx("Button_Press", "SFX")
	GameManager.show_resort_sheep_names = not GameManager.show_resort_sheep_names
	_refresh_toggle_names_button()
	for g in get_tree().get_nodes_in_group("resort_guests"):
		if is_instance_valid(g) and g is ResortGuest and is_instance_valid(g.name_label):
			g.name_label.visible = GameManager.show_resort_sheep_names

func _refresh_toggle_names_button() -> void:
	if is_instance_valid(toggle_names_button):
		toggle_names_button.text = "Name"
		if GameManager.show_resort_sheep_names:
			toggle_names_button.modulate = Color.WHITE
			toggle_names_button.tooltip_text = "Sheep Names: Visible (Click to Hide)"
		else:
			toggle_names_button.modulate = Color(0.55, 0.55, 0.55, 0.65)
			toggle_names_button.tooltip_text = "Sheep Names: Hidden (Click to Show)"

func _setup_special_upgrade_controls() -> void:
	# 1. Double Speed toggle button (bottom-right, left of ToggleNamesButton, scaled up 50%)
	speed_toggle_button = Button.new()
	speed_toggle_button.name = "SpeedToggleButton"
	speed_toggle_button.custom_minimum_size = Vector2(165, 66)
	speed_toggle_button.size = Vector2(165, 66)
	speed_toggle_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_toggle_button.anchor_left = 1.0
	speed_toggle_button.anchor_top = 1.0
	speed_toggle_button.anchor_right = 1.0
	speed_toggle_button.anchor_bottom = 1.0
	speed_toggle_button.offset_left = -301.0
	speed_toggle_button.offset_top = -82.0
	speed_toggle_button.offset_right = -136.0
	speed_toggle_button.offset_bottom = -16.0
	speed_toggle_button.focus_mode = Control.FOCUS_NONE
	speed_toggle_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	speed_toggle_button.add_theme_font_size_override("font_size", 21)
	speed_toggle_button.pressed.connect(toggle_double_speed)
	$UILayer.add_child(speed_toggle_button)

	# 2. Freeze Bomb active item button (bottom-right, left of SpeedToggleButton, scaled up 50%)
	freeze_bomb_button = Button.new()
	freeze_bomb_button.name = "FreezeBombButton"
	freeze_bomb_button.custom_minimum_size = Vector2(248, 66)
	freeze_bomb_button.size = Vector2(248, 66)
	freeze_bomb_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	freeze_bomb_button.anchor_left = 1.0
	freeze_bomb_button.anchor_top = 1.0
	freeze_bomb_button.anchor_right = 1.0
	freeze_bomb_button.anchor_bottom = 1.0
	freeze_bomb_button.offset_left = -559.0
	freeze_bomb_button.offset_top = -82.0
	freeze_bomb_button.offset_right = -311.0
	freeze_bomb_button.offset_bottom = -16.0
	freeze_bomb_button.focus_mode = Control.FOCUS_NONE
	freeze_bomb_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	freeze_bomb_button.add_theme_font_size_override("font_size", 21)
	freeze_bomb_button.pressed.connect(_on_freeze_bomb_button_pressed)
	$UILayer.add_child(freeze_bomb_button)

	# 3. World-space Freeze Bomb targeting circle indicator
	freeze_aim_indicator = Node2D.new()
	freeze_aim_indicator.name = "FreezeAimIndicator"
	freeze_aim_indicator.z_index = 65
	freeze_aim_indicator.visible = false
	freeze_aim_indicator.draw.connect(_on_freeze_aim_indicator_draw)
	$WorldRoot.add_child(freeze_aim_indicator)

	_refresh_special_upgrade_controls()

func toggle_double_speed() -> void:
	SfxManager.play_sfx("Fast", "SFX")
	if not is_active or not GameManager.has_double_speed():
		return
	is_double_speed = not is_double_speed
	
	Engine.time_scale = 2.0 if is_double_speed else 1.0
	_refresh_special_upgrade_controls()

func _on_freeze_bomb_button_pressed() -> void:
	if not is_active:
		return
	if GameManager.is_aiming_freeze_bomb:
		_set_freeze_bomb_aiming(false)
		return
	if GameManager.get_freeze_bomb_count() <= 0:
		return
	_set_freeze_bomb_aiming(true)

func _set_freeze_bomb_aiming(aiming: bool) -> void:
	GameManager.is_aiming_freeze_bomb = aiming
	if is_instance_valid(freeze_aim_indicator):
		freeze_aim_indicator.visible = aiming
		if aiming:
			freeze_aim_indicator.global_position = get_global_mouse_position()
			freeze_aim_indicator.queue_redraw()
	_refresh_special_upgrade_controls()

func _on_freeze_aim_indicator_draw() -> void:
	if not is_instance_valid(freeze_aim_indicator):
		return
	freeze_aim_indicator.draw_circle(Vector2.ZERO, FREEZE_BOMB_RADIUS, Color(0.35, 0.85, 1.0, 0.22))
	freeze_aim_indicator.draw_arc(Vector2.ZERO, FREEZE_BOMB_RADIUS, 0.0, TAU, 48, Color(0.55, 0.95, 1.0, 0.92), 3.0, true)
	freeze_aim_indicator.draw_arc(Vector2.ZERO, FREEZE_BOMB_RADIUS * 0.45, 0.0, TAU, 32, Color(0.75, 0.98, 1.0, 0.55), 1.5, true)

func detonate_freeze_bomb_at(world_pos: Vector2) -> int:
	if not GameManager.consume_freeze_bomb():
		_set_freeze_bomb_aiming(false)
		return 0
	_set_freeze_bomb_aiming(false)

	var frozen_count: int = 0
	SfxManager.play_sfx("boulderBreak", "SFX")
	for g in get_tree().get_nodes_in_group("resort_guests"):
		if is_instance_valid(g) and g is ResortGuest:
			var rg: ResortGuest = g as ResortGuest
			if rg.state != ResortGuest.State.IN_FACILITY and rg.state != ResortGuest.State.EXITING and rg.state != ResortGuest.State.PICKED_UP:
				if rg.global_position.distance_to(world_pos) <= FREEZE_BOMB_RADIUS:
					rg.apply_freeze(FREEZE_BOMB_DURATION)
					frozen_count += 1

	_spawn_freeze_explosion_vfx(world_pos, frozen_count)
	_refresh_hud()
	return frozen_count

func _spawn_freeze_explosion_vfx(world_pos: Vector2, frozen_count: int) -> void:
	var vfx := Node2D.new()
	vfx.global_position = world_pos
	vfx.z_index = 62
	$WorldRoot.add_child(vfx)
	vfx.set_meta("radius_scale", 0.2)
	vfx.set_meta("alpha", 1.0)
	vfx.draw.connect(func():
		var r_s: float = float(vfx.get_meta("radius_scale", 1.0))
		var a: float = float(vfx.get_meta("alpha", 1.0))
		var rad: float = FREEZE_BOMB_RADIUS * r_s
		vfx.draw_circle(Vector2.ZERO, rad, Color(0.45, 0.92, 1.0, 0.35 * a))
		vfx.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 48, Color(0.75, 0.98, 1.0, 0.95 * a), 4.0, true)
	)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_method(func(val: float):
		if is_instance_valid(vfx):
			vfx.set_meta("radius_scale", val)
			vfx.queue_redraw()
	, 0.2, 1.05, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_method(func(val: float):
		if is_instance_valid(vfx):
			vfx.set_meta("alpha", val)
			vfx.queue_redraw()
	, 1.0, 0.0, 0.45)
	t.chain().tween_callback(vfx.queue_free)

	var lbl := Label.new()
	lbl.text = "❄ FROZE %d SHEEP!" % frozen_count if frozen_count > 0 else "❄ FREEZE!"
	lbl.modulate = Color(0.55, 0.95, 1.0, 1.0)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.15, 0.25, 0.95))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = world_pos + Vector2(-90, -25)
	lbl.size = Vector2(180, 30)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 66
	$WorldRoot.add_child(lbl)
	var lt := create_tween()
	lt.set_parallel(true)
	lt.tween_property(lbl, "position:y", lbl.position.y - 42.0, 1.0).set_trans(Tween.TRANS_CUBIC)
	lt.tween_property(lbl, "modulate:a", 0.0, 1.0)
	lt.chain().tween_callback(lbl.queue_free)

func _refresh_special_upgrade_controls() -> void:
	if is_instance_valid(speed_toggle_button):
		var unlocked: bool = GameManager.has_double_speed()
		speed_toggle_button.visible = unlocked and is_active
		if is_double_speed:
			speed_toggle_button.text = "⏩ 2x SPEED"
			speed_toggle_button.modulate = Color(1.0, 0.9, 0.35, 1.0)
			speed_toggle_button.tooltip_text = "Running at 2x Speed (Click for 1x)"
		else:
			speed_toggle_button.text = "▶ 1x SPEED"
			speed_toggle_button.modulate = Color.WHITE
			speed_toggle_button.tooltip_text = "Running at 1x Speed (Click for 2x)"

	if is_instance_valid(freeze_bomb_button):
		var bomb_count: int = GameManager.get_freeze_bomb_count()
		freeze_bomb_button.visible = is_active and (bomb_count > 0 or GameManager.is_aiming_freeze_bomb)
		# Shift Freeze Bomb button nicely if Speed button is hidden
		if is_instance_valid(speed_toggle_button) and not speed_toggle_button.visible:
			freeze_bomb_button.offset_left = -384.0
			freeze_bomb_button.offset_right = -136.0
		else:
			freeze_bomb_button.offset_left = -559.0
			freeze_bomb_button.offset_right = -311.0

		if GameManager.is_aiming_freeze_bomb:
			freeze_bomb_button.text = "❄ AIMING... (Cancel)"
			freeze_bomb_button.modulate = Color(0.5, 0.95, 1.0, 1.0)
			freeze_bomb_button.tooltip_text = "Left-click on pasture to freeze sheep! Right-click or click here to cancel."
		else:
			freeze_bomb_button.text = "❄ Freeze Bomb (x%d)" % bomb_count
			freeze_bomb_button.modulate = Color(0.82, 0.96, 1.0, 1.0)
			freeze_bomb_button.tooltip_text = "Click to aim a Freeze Bomb (freezes sheep in a small circle for %.0fs)" % FREEZE_BOMB_DURATION

func _init_layout_edit_mode(pathways: PathwaysRenderer) -> void:
	is_active = false

	# Raise UILayer above the layout editor UI (which uses layer 20)
	$UILayer.layer = 30

	# Hide rush hour HUD elements instead of the entire UILayer so PauseMenu stays functional
	if has_node("UILayer/TopHUD"):
		$UILayer/TopHUD.visible = false
	if is_instance_valid(toggle_names_button):
		toggle_names_button.visible = false
	if is_instance_valid(speed_toggle_button):
		speed_toggle_button.visible = false
	if is_instance_valid(freeze_bomb_button):
		freeze_bomb_button.visible = false

	camera.position = Vector2(-240, 180)
	if camera.has_method("set_zoom_level"):
		camera.set_zoom_level(0.85)
	else:
		camera.zoom = Vector2(0.85, 0.85)

	layout_editor = RESORT_LAYOUT_EDITOR.new()
	layout_editor.name = "ResortLayoutEditor"
	add_child(layout_editor)
	layout_editor.setup(self, facilities_container, pathways)
	_on_camera_zoom_changed(camera.zoom.x)

func _on_camera_zoom_changed(current_zoom: float) -> void:
	if is_instance_valid(facilities_container):
		for child in facilities_container.get_children():
			if child is Facility and is_instance_valid(child) and child.has_method("update_text_zoom"):
				child.update_text_zoom(current_zoom)
	if is_instance_valid(guests_container):
		for g in guests_container.get_children():
			if g is ResortGuest and is_instance_valid(g) and g.has_method("update_text_zoom"):
				g.update_text_zoom(current_zoom)
	if is_instance_valid(layout_editor) and layout_editor.has_method("update_text_zoom"):
		layout_editor.update_text_zoom(current_zoom)

func _apply_resort_layout() -> void:
	if GameManager.resort_layout.has("facility_instances") and not GameManager.resort_layout["facility_instances"].is_empty():
		var inst_list: Array = GameManager.resort_layout["facility_instances"]
		# Clear default static facilities and instantiate from saved facility_instances list
		for child in facilities_container.get_children():
			facilities_container.remove_child(child)
			child.queue_free()
		for item in inst_list:
			if item is Dictionary:
				create_facility_instance(
					item.get("facility_id", "restaurant"),
					item.get("position", Vector2.ZERO),
					item.get("name", ""),
					item.get("display_name", "")
				)
		return

	if not GameManager.resort_layout.has("facilities"):
		return
	var fac_pos: Dictionary = GameManager.resort_layout["facilities"]
	for child in facilities_container.get_children():
		if fac_pos.has(child.name):
			child.position = fac_pos[child.name]
		elif child is Facility:
			for key in fac_pos.keys():
				if _matches_facility_id(child.facility_id, key.to_snake_case()):
					child.position = fac_pos[key]

func create_facility_instance(fac_id: String, pos: Vector2, custom_node_name: String = "", custom_display: String = "") -> Facility:
	var tmpl: Dictionary = GameManager.FACILITY_TEMPLATES.get(fac_id, {})
	var fac: Facility = FACILITY_SCENE.instantiate()
	fac.facility_id = fac_id
	if not tmpl.is_empty():
		fac.display_name = custom_display if custom_display != "" else tmpl.get("display_name", "Facility")
		fac.base_cycle_time = tmpl.get("base_cycle_time", 5.0)
		fac.base_payout = tmpl.get("base_payout", 15)
		fac.building_row = tmpl.get("building_row", 8)
		var sheet_path: String = tmpl.get("sheet_path", "res://assets/PhaseII_Map/Buildings1.png")
		if ResourceLoader.exists(sheet_path):
			fac.building_texture = load(sheet_path) as Texture2D
		var pref_arr: Array = tmpl.get("preferred_species", [])
		if not pref_arr.is_empty():
			var typed_prefs: Array[String] = []
			for s in pref_arr:
				typed_prefs.append(str(s))
			fac.preferred_species = typed_prefs
	elif fac_id == "main_building":
		fac.display_name = "Main Building"
		fac.base_cycle_time = 0.0
		fac.base_payout = 0
		fac.building_row = 8
	else:
		fac.display_name = custom_display if custom_display != "" else "Facility"
	fac.position = pos
	if custom_node_name != "":
		fac.name = custom_node_name
	else:
		var count: int = 1
		for c in facilities_container.get_children():
			if c is Facility and _matches_facility_id(c.facility_id, fac_id):
				count += 1
		fac.name = "%s_%d" % [fac_id.to_pascal_case(), count]
	facilities_container.add_child(fac)
	if fac.has_method("update_text_zoom") and is_instance_valid(camera):
		fac.update_text_zoom(camera.zoom.x)
	return fac

func rebuild_grass_tilemap() -> void:
	var grass_layer: TileMapLayer = $TileMap/Grass if has_node("TileMap/Grass") else null
	if not is_instance_valid(grass_layer):
		return
	var land_cells: Array = GameManager.resort_layout.get("land_cells", [])
	if land_cells.is_empty():
		return
	grass_layer.clear()
	var subtile_cells: Array[Vector2i] = []
	for cell in land_cells:
		if not cell is Vector2i:
			continue
		var bx: int = cell.x * 2
		var by: int = cell.y * 2
		subtile_cells.append(Vector2i(bx, by))
		subtile_cells.append(Vector2i(bx + 1, by))
		subtile_cells.append(Vector2i(bx, by + 1))
		subtile_cells.append(Vector2i(bx + 1, by + 1))
	if not subtile_cells.is_empty():
		# Terrain Set 1, Terrain 0 = "Grass" in resort_tileset_ground.tres
		grass_layer.set_cells_terrain_connect(subtile_cells, 1, 0, false)

func _setup_pathways() -> PathwaysRenderer:
	var pathways := PathwaysRenderer.new()
	pathways.name = "PathwaysRenderer"
	$WorldRoot.add_child(pathways)
	$WorldRoot.move_child(pathways, 0)
	return pathways

func _matches_facility_id(fac_id: String, pref_id: String) -> bool:
	return fac_id == pref_id

var _last_displayed_sec: int = -1

func _process(delta: float) -> void:
	if not is_active:
		return

	if GameManager.is_aiming_freeze_bomb and is_instance_valid(freeze_aim_indicator):
		freeze_aim_indicator.global_position = get_global_mouse_position()
		freeze_aim_indicator.queue_redraw()

	time_left -= delta
	var cur_sec: int = int(time_left)
	if cur_sec != _last_displayed_sec:
		_last_displayed_sec = cur_sec
		hud_timer_label.text = "Rush Hour: %02d:%02d" % [int(time_left / 60.0), int(fmod(time_left, 60.0))]

	if time_left <= 0.0:
		time_left = 0.0
		_end_rush_hour()

func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if GameManager.is_aiming_freeze_bomb:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				detonate_freeze_bomb_at(get_global_mouse_position())
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_set_freeze_bomb_aiming(false)
				get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_set_freeze_bomb_aiming(false)
			get_viewport().set_input_as_handled()

func _refresh_hud() -> void:
	hud_timer_label.text = "Rush Hour: %02d:%02d" % [int(time_left / 60.0), int(fmod(time_left, 60.0))]
	hud_money_label.text = "Earned: +$%d" % (resort_revenue + resort_tips - resort_damages)
	hud_guests_label.text = "Guests: %d" % active_guests.size()
	hud_wolves_label.text = "Wolves Deported: %d" % wolves_caught
	_refresh_special_upgrade_controls()

## Ensures Phase II has wolf infiltration proportional to guest population,
## and schedules all spawns so no wolf ever spawns in the last 15 seconds.
func _inject_dynamic_wolves() -> void:
	var total_sheep: int = guest_queue.size()
	var current_wolves: int = 0
	for g in guest_queue:
		if g is Dictionary and g.get("is_wolf", false):
			current_wolves += 1

	var target_wolves: int = 1
	if total_sheep >= 12:
		target_wolves = 3
	elif total_sheep >= 7:
		target_wolves = 2
	else:
		target_wolves = 1

	sneak_in_wolves_spawned = 0
	if current_wolves < target_wolves:
		var needed: int = target_wolves - current_wolves
		for i in range(needed):
			var sneak_wolf: Dictionary = GameManager.make_dev_guest(true, 90 + i)
			sneak_wolf["is_sneak_wolf"] = true
			# Insert in the first 65% of the queue so it never spawns near the last 15s
			var max_idx: int = maxi(1, int(floor(guest_queue.size() * 0.65)))
			var insert_idx: int = clampi(1 + i * 2, 0, max_idx)
			guest_queue.insert(insert_idx, sneak_wolf)
			sneak_in_wolves_spawned += 1

	# Pace spawn_interval so the entire guest_queue finishes spawning by t = 28s left (well before 15s cutoff)
	var max_spawn_window: float = RUSH_HOUR_DURATION - NO_WOLF_SPAWN_CUTOFF - 12.0 # ~33s window
	if guest_queue.size() > 1:
		spawn_interval = clampf(max_spawn_window / float(guest_queue.size()), 0.75, 1.7)
	else:
		spawn_interval = 1.5

func _spawn_next_guest() -> void:
	if not is_active or guest_queue.is_empty():
		return

	var data: Dictionary = guest_queue.pop_front()
	# Guarantee no wolf spawns during the last 15 seconds of the round
	if time_left <= NO_WOLF_SPAWN_CUTOFF and data.get("is_wolf", false):
		data = data.duplicate(true)
		data["is_wolf"] = false

	spawn_guest_from_data(data)

	# Schedule next spawn
	if not guest_queue.is_empty():
		var timer := get_tree().create_timer(spawn_interval)
		timer.timeout.connect(_spawn_next_guest)

func _get_spawn_position() -> Vector2:
	# Spawn from the Main Building if present
	for f in facilities_container.get_children():
		if f is Facility and f.facility_id == "main_building":
			# If Main Building is at the bottom of the cross pathway (y > 0), spawn at its north pathway edge
			if f.global_position.y > 40.0:
				return f.global_position + Vector2(0, -48.0)
			return f.get_slot_position()
	return entrance_marker.global_position

func spawn_guest_from_data(data: Dictionary) -> ResortGuest:
	var guest: ResortGuest = GUEST_SCENE.instantiate()
	guests_container.add_child(guest)
	var spawn_pos := _get_spawn_position()
	guest.global_position = spawn_pos
	guest.setup(data)
	# Step forward onto the cross pathway toward the center
	var step_y: float = -38.0 if spawn_pos.y > 40.0 else 45.0
	guest.target_pos = spawn_pos + Vector2(randf_range(-16, 16), step_y)

	guest.guest_ready_for_facility.connect(_assign_guest_to_facility)
	guest.wolf_deported.connect(_on_wolf_deported)
	if guest.has_method("update_text_zoom") and is_instance_valid(camera):
		guest.update_text_zoom(camera.zoom.x)
	active_guests.append(guest)
	_refresh_hud()
	return guest

func _assign_guest_to_facility(guest) -> void:
	if not is_instance_valid(guest):
		return
	if guest.get("is_influencer"):
		guest.wander_for(randf_range(3.0, 5.0))
		return

	# First preference: match preferred facility (excluding previous facility)
	var preferred_candidates: Array = []
	for f in facilities:
		if f != guest.last_facility and _matches_facility_id(f.facility_id, guest.preferred_facility_id) and f.can_accept_guest():
			preferred_candidates.append(f)

	var target = null
	if not preferred_candidates.is_empty():
		target = preferred_candidates.pick_random()
		
	# Fallback: any other open facility (excluding previous facility)
	if target == null:
		var fallback_candidates: Array = []
		for f in facilities:
			if f != guest.last_facility and f.can_accept_guest():
				fallback_candidates.append(f)
		if not fallback_candidates.is_empty():
			target = fallback_candidates.pick_random()

	if target != null:
		guest.target_facility = target
		guest.state = ResortGuest.State.SEEKING_FACILITY
	else:
		# No other facility free right now: wander and retry
		guest.wander_for(randf_range(2.0, 3.5))

func _on_payout_earned(amount: int, _fac_name: String) -> void:
	if not is_active:
		return
	resort_revenue += amount
	SfxManager.play_sfx("Pickup_coins", "SFX")
	_refresh_hud()

func _on_facility_broken(_fac_name: String) -> void:
	SfxManager.play_sfx("Faci_break", "SFX")
	if not is_active:
		return
	resort_damages += 10
	_refresh_hud()

func _on_tip_bubble_requested(spawn_pos: Vector2, bonus: int) -> void:
	if not is_active:
		return
	var bubble = BUBBLE_SCENE.instantiate()
	bubble.bonus_amount = bonus
	bubble.global_position = spawn_pos
	bubble.bubble_popped.connect(func(payout: int):
		resort_tips += payout
		_refresh_hud()
	)
	bubbles_container.add_child(bubble)

func _on_wolf_deported(guest) -> void:
	SfxManager.play_sfx("jail", "SFX")
	wolves_caught += 1
	active_guests.erase(guest)
	GameManager.wolves_caught_in_resort += 1
	# Award deportation bounty + reputation
	resort_tips += 12
	GameManager.reputation = clampi(GameManager.reputation + 3, 0, 100)
	_refresh_hud()

func _on_innocent_jailed(_guest: Node2D) -> void:
	if not is_active:
		return
	innocents_jailed += 1
	SfxManager.play_sfx("jail_wrong", "SFX")
	GameManager.reputation = clampi(GameManager.reputation - 1, 0, 100)
	_refresh_hud()

func _end_rush_hour() -> void:
	SfxManager.play_sfx("Endshift_day", "SFX")
	is_active = false
	is_double_speed = false
	Engine.time_scale = 1.0
	_set_freeze_bomb_aiming(false)
	_refresh_special_upgrade_controls()

	# Gently release any held sheep/wolf back onto the ground before freezing the world
	for g in active_guests:
		if is_instance_valid(g) and g.has_method("force_release_on_round_end"):
			g.force_release_on_round_end()

	# Freeze the resort world: stop movement, guest actions, facilities, bubbles, and timers
	$WorldRoot.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Count any wolves that escaped without being deported, and collect surviving innocent sheep for Long Visit
	var escaped_wolves := 0
	var surviving_innocents: Array = []
	for g in active_guests:
		if is_instance_valid(g):
			if g.is_wolf:
				escaped_wolves += 1
			elif not g.is_influencer and not g.guest_data.is_empty():
				surviving_innocents.append(g.guest_data)
	for q_data in guest_queue:
		if q_data is Dictionary and not q_data.get("is_wolf", false) and not q_data.get("is_influencer", false):
			surviving_innocents.append(q_data)
	GameManager.wolves_escaped_unharmed = escaped_wolves
	GameManager.save_stayover_candidates(surviving_innocents)
	GameManager.admitted_guests.clear()

	# Count facilities left broken at the end of Rush Hour
	var broken_facilities_count: int = 0
	for f in facilities:
		if is_instance_valid(f) and f.is_broken:
			broken_facilities_count += 1

	# Apply end-of-round reputation penalties
	var escaped_rep_loss: int = escaped_wolves * 6
	var broken_rep_loss: int = broken_facilities_count * 3
	GameManager.reputation = clampi(GameManager.reputation - escaped_rep_loss - broken_rep_loss, 0, 100)

	# Update total economy in GameManager
	var net_profit: int = resort_revenue + resort_tips - resort_damages
	GameManager.money += net_profit
	GameManager.phase2_revenue = resort_revenue
	GameManager.phase2_tips = resort_tips
	GameManager.phase2_damages = resort_damages
	GameManager.week["earned"] = int(GameManager.week.get("earned", 0)) + net_profit
	GameManager.week["wolves_caught"] = int(GameManager.week.get("wolves_caught", 0)) + wolves_caught

	if is_instance_valid(next_day_button):
		next_day_button.text = "Finish Week ▶" if GameManager.current_day >= DayRules.LAST_DAY else "Continue to Next Day ▶"

	# Display End-of-Day Rush Hour Ledger
	var summary: String = "[center][font_size=26][b]RESORT RUSH HOUR COMPLETE![/b][/font_size][/center]\n\n"
	summary += "• Facility Revenue: [color=#55dd55]+$%d[/color]\n" % resort_revenue
	summary += "• Tip Bubbles & Bounties: [color=#55dd55]+$%d[/color]\n" % resort_tips
	summary += "• Sabotage & Damage Costs: [color=#ff5555]-$%d[/color]\n" % resort_damages
	summary += "[b]NET RESORT PROFIT: $%d[/b]  (Balance: $%d)\n\n" % [net_profit, GameManager.money]

	if GameManager.last_stayover_count > 0:
		summary += "[color=#88ddff]🏡 %d sheep stayed over from yesterday (Long Visit)![/color]\n" % GameManager.last_stayover_count
	if wolves_caught > 0:
		summary += "[color=#44ff88]★ %d wolf deported: +%d Rep[/color]\n" % [wolves_caught, wolves_caught * 3]
	if innocents_jailed > 0:
		summary += "[color=#ffaa44]• %d innocent sheep wrongly jailed: -%d Rep[/color]\n" % [innocents_jailed, innocents_jailed]
	if escaped_wolves > 0:
		summary += "[color=#ff5555]⚠ %d wolf escaped undetected: -%d Rep[/color]\n" % [escaped_wolves, escaped_rep_loss]
	if broken_facilities_count > 0:
		summary += "[color=#ff5555]🔧 %d facility left broken at closing: -%d Rep[/color]\n" % [broken_facilities_count, broken_rep_loss]
	summary += "[b]Current Reputation: %d / 100[/b]\n" % GameManager.reputation

	ledger_text.text = summary
	ledger_panel.visible = true
	

func _exit_tree() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if is_instance_valid(GameManager):
		GameManager.is_aiming_freeze_bomb = false

func _on_next_day_pressed() -> void:
	SfxManager.play_sfx("Button_Press", "SFX")

	# Tutorial Continue button
	if is_tutorial_active:
		is_tutorial_active = false
		ledger_panel.visible = false
		get_tree().paused = false

		next_day_button.text = "Continue to Rush Hour ▶"
		SfxManager.play_sfx("Button_Press")
		
		is_active = true
		_refresh_hud()
		_spawn_next_guest()
		return

	# Normal end-of-day progression
	SfxManager.stop_sfx("phase2theme")
	GameManager.current_day += 1
	GameManager.reset_day_pool()

	if GameManager.current_day <= DayRules.LAST_DAY:
		SaveLoad.save_game()
	else:
		SaveLoad.delete_save()

	GameManager.change_scene("res://scene/front_desk.tscn")

func _generate_fallback_pool() -> void:
	# Generates a quick test queue when running Phase 2 directly from editor:
	# real generated guests (so each has its drawn sheep), 1 undercover wolf.
	for i in 6:
		guest_queue.append(GameManager.make_dev_guest(i == 4, i + 1))
