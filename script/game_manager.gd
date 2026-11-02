extends Node
## Global game manager handling cross-phase progression, economic ledger,
## and configuration between the Front Desk (Phase 1) and Resort (Phase 2).

## Set to true to enable the full Phase 1 -> Phase 2 loop.
## Set to false for the standalone Phase 1 course demo.
var ENABLE_PHASE_2: bool = true

# Run progression
var run_started: bool = false
var run_seed: int = 0
var current_day: int = 1
var money: int = 150
var reputation: int = 70
var residents: int = 0
var wolves_admitted_total: int = 0
var guest_book: Array = []
var week: Dictionary = {"processed": 0, "correct": 0, "wolves_caught": 0, "residents": 0, "quota_days": 0, "earned": 0}

# Pool of admitted guests for today's Phase 2 resort rush
# Each entry is the full guest dictionary from SheepGenerator
var admitted_guests: Array = []
var wolves_in_pool: int = 0

# Results from Phase 2 to feed into ledger and overnight reports
var phase2_revenue: int = 0
var phase2_tips: int = 0
var phase2_damages: int = 0
var wolves_caught_in_resort: int = 0
var wolves_escaped_unharmed: int = 0

# Species facility affinity mapping
const PREFERRED_FACILITIES := {
	"Merino": "wool_salon",
	"Shetland": "wool_salon",
	"Suffolk": "restaurant",
	"Dorper": "restaurant",
	"Cheviot": "cabin",
	"Jacob": "cabin",
	"Texel": "restaurant",
	"Romney": "cabin",
}

# Resort Layout & Pathway Planning (Phase 3 Desk Tool)
const PATH_CELL_SIZE: float = 32.0
const BUILDING_COST: int = 50

const FACILITY_TEMPLATES := {
	"cabin": {
		"facility_id": "cabin",
		"display_name": "Cabin",
		"base_cycle_time": 7.5,
		"base_payout": 35,
		"building_row": 0,
		"cost": BUILDING_COST,
	},
	"restaurant": {
		"facility_id": "restaurant",
		"display_name": "Restaurant",
		"base_cycle_time": 4.5,
		"base_payout": 15,
		"building_row": 7,
		"cost": BUILDING_COST,
	},
	"wool_salon": {
		"facility_id": "wool_salon",
		"display_name": "Wool Salon",
		"base_cycle_time": 11.0,
		"base_payout": 65,
		"building_row": 13,
		"cost": BUILDING_COST,
	},
	"jail": {
		"facility_id": "jail",
		"display_name": "Jail",
		"base_cycle_time": 3.5,
		"base_payout": 0,
		"building_row": 11,
		"cost": BUILDING_COST,
	},
}

const DEFAULT_FACILITY_INSTANCES := [
	{
		"name": "MainBuilding",
		"facility_id": "main_building",
		"display_name": "Main Building",
		"position": Vector2(0, -170),
		"building_row": 8,
		"base_cycle_time": 0.0,
		"base_payout": 0,
	},
	{
		"name": "CabinFacility",
		"facility_id": "cabin",
		"display_name": "Cabin",
		"position": Vector2(0, 70),
		"building_row": 0,
		"base_cycle_time": 7.5,
		"base_payout": 35,
	},
	{
		"name": "CloverMeadow",
		"facility_id": "restaurant",
		"display_name": "Restaurant",
		"position": Vector2(-260, -90),
		"building_row": 7,
		"base_cycle_time": 4.5,
		"base_payout": 15,
	},
	{
		"name": "ShearingBoutique",
		"facility_id": "wool_salon",
		"display_name": "Wool Salon",
		"position": Vector2(260, -90),
		"building_row": 13,
		"base_cycle_time": 11.0,
		"base_payout": 65,
	},
	{
		"name": "JailFacility",
		"facility_id": "jail",
		"display_name": "Jail",
		"position": Vector2(-310, 110),
		"building_row": 11,
		"base_cycle_time": 3.5,
		"base_payout": 0,
	},
]

const DEFAULT_FACILITY_POSITIONS := {
	"MainBuilding": Vector2(0, -170),
	"CabinFacility": Vector2(0, 70),
	"Cabin": Vector2(0, 70),
	"CloverMeadow": Vector2(-260, -90),
	"ThermalMudBath": Vector2(0, 70),
	"ShearingBoutique": Vector2(260, -90),
	"Restaurant": Vector2(-260, -90),
	"WoolSalon": Vector2(260, -90),
	"Jail": Vector2(-310, 110),
	"JailFacility": Vector2(-310, 110),
}

var resort_layout: Dictionary = {}
var path_cell_lookup: Dictionary = {}
var is_layout_edit_mode: bool = false
var dev_pending_week_report: Dictionary = {}
var dev_menu: CanvasLayer = null

# Scene Transition Manager
var transition_layer: CanvasLayer = null
var transition_overlay: ColorRect = null
var is_transitioning: bool = false

func _ready() -> void:
	init_default_layout()
	_setup_transition_overlay()
	if DisplayServer.get_name() != "headless" and ResourceLoader.exists("res://script/dev_menu.gd"):
		var dev_script := load("res://script/dev_menu.gd")
		if dev_script:
			dev_menu = dev_script.new()
			dev_menu.name = "DevMenu"
			add_child(dev_menu)

func _setup_transition_overlay() -> void:
	transition_layer = CanvasLayer.new()
	transition_layer.name = "TransitionLayer"
	transition_layer.layer = 128 # Ensure it sits above all UI layers
	add_child(transition_layer)

	transition_overlay = ColorRect.new()
	transition_overlay.name = "TransitionOverlay"
	transition_overlay.color = Color.BLACK
	transition_overlay.modulate.a = 0.0
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition_layer.add_child(transition_overlay)

## Smoothly fades to black, changes the scene, and fades back in.
func change_scene(target_path: String, fade_duration: float = 0.35) -> void:
	if is_transitioning:
		return
	is_transitioning = true

	if not transition_overlay:
		_setup_transition_overlay()

	# Block all player mouse clicks during the fade
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# Fade to Black
	var tween_out := create_tween()
	tween_out.tween_property(transition_overlay, "modulate:a", 1.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween_out.finished

	# Change scene file
	get_tree().change_scene_to_file(target_path)

	# Wait a frame so the new scene is instantiated and ready
	await get_tree().process_frame

	# Fade in from Black
	var tween_in := create_tween()
	tween_in.tween_property(transition_overlay, "modulate:a", 0.0, fade_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween_in.finished

	# Release mouse filter and transition lock
	transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false

func init_default_layout() -> void:
	if resort_layout.is_empty():
		var paths: Array = []
		# Default central boulevard from entrance (y=310 -> cell y=9) up to crossroads (y=-90 -> cell y=-3)
		for y in range(-3, 11):
			paths.append(Vector2i(0, y))
		# Default horizontal promenade connecting left to right facilities
		for x in range(-8, 9):
			paths.append(Vector2i(x, -3))
		# Default spur leading up to Thermal Mud Bath
		for y in range(-6, -3):
			paths.append(Vector2i(0, y))
		# Default path branch leading left to the Jail
		for x in range(-9, 1):
			paths.append(Vector2i(x, 3))

		save_resort_layout(DEFAULT_FACILITY_POSITIONS.duplicate(), paths, DEFAULT_FACILITY_INSTANCES.duplicate(true))

func save_resort_layout(fac_positions: Dictionary, paths: Array, fac_instances: Array = []) -> void:
	var instances_copy: Array = []
	if not fac_instances.is_empty():
		instances_copy = fac_instances.duplicate(true)
	elif resort_layout.has("facility_instances"):
		instances_copy = resort_layout["facility_instances"].duplicate(true)
	else:
		instances_copy = DEFAULT_FACILITY_INSTANCES.duplicate(true)

	resort_layout = {
		"facilities": fac_positions.duplicate(),
		"pathways": paths.duplicate(),
		"facility_instances": instances_copy,
	}
	path_cell_lookup.clear()
	for cell in paths:
		if cell is Vector2i:
			path_cell_lookup[cell] = true

func get_facility_position(fac_name: String) -> Vector2:
	if resort_layout.has("facilities"):
		var facs: Dictionary = resort_layout["facilities"]
		if facs.has(fac_name):
			return facs[fac_name]
		# Fallback matching case/snake
		for key in facs.keys():
			if key.to_snake_case() == fac_name.to_snake_case():
				return facs[key]
	return DEFAULT_FACILITY_POSITIONS.get(fac_name, Vector2.ZERO)

func is_world_pos_on_path(world_pos: Vector2) -> bool:
	var cell := world_to_path_cell(world_pos)
	return path_cell_lookup.has(cell)

func world_to_path_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / PATH_CELL_SIZE)), int(floor(world_pos.y / PATH_CELL_SIZE)))

func path_cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * PATH_CELL_SIZE + PATH_CELL_SIZE * 0.5, cell.y * PATH_CELL_SIZE + PATH_CELL_SIZE * 0.5)

func reset_day_pool() -> void:
	admitted_guests.clear()
	wolves_in_pool = 0
	phase2_revenue = 0
	phase2_tips = 0
	phase2_damages = 0
	wolves_caught_in_resort = 0
	wolves_escaped_unharmed = 0

func record_admitted_guest(guest: Dictionary) -> void:
	admitted_guests.append(guest)
	if guest.get("is_wolf", false):
		wolves_in_pool += 1

func get_preferred_facility(species: String) -> String:
	return PREFERRED_FACILITIES.get(species, "restaurant")

func make_dev_guest(is_wolf: bool, idx: int = 1) -> Dictionary:
	var gen := SheepGenerator.new(randi(), DayRules.for_day(clampi(current_day, 1, DayRules.LAST_DAY)))
	var used_ids := {}
	var truth := gen._make_identity(used_ids)
	if is_wolf:
		truth.name = "%s (Wolf #%d)" % [truth.name, idx] if false else truth.name
	var g := gen._make_guest(truth, true, is_wolf, false)
	return g

func build_custom_phase2_pool(sheep_count: int, wolf_count: int) -> void:
	reset_day_pool()
	var pool: Array = []
	for i in range(maxi(sheep_count, 0)):
		pool.append(make_dev_guest(false, i + 1))
	for j in range(maxi(wolf_count, 0)):
		pool.append(make_dev_guest(true, j + 1))
	pool.shuffle()
	for guest in pool:
		record_admitted_guest(guest)
