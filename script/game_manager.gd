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
	"Shetland": "clock_tower",
	"Suffolk": "restaurant",
	"Dorper": "gift_shop",
	"Cheviot": "bakery",
	"Jacob": "cabin",
	"Texel": "restaurant",
	"Romney": "cabin",
}

# Resort Layout & Pathway Planning (Phase 3 Desk Tool)
const PATH_CELL_SIZE: float = 32.0
const BUILDING_COST: int = 50
const LAND_TILE_COST: int = 5
const COMBO_RANGE: float = 220.0

const SHOP_FACILITY_ORDER: Array[String] = [
	"cabin",
	"restaurant",
	"wool_salon",
	"bakery",
	"gift_shop",
	"clock_tower",
]

# Full resort map grid bounds in 32x32 cells (32x24 cells = 64x48 16x16 grass tiles)
const MAP_MIN_CELL_X: int = -16
const MAP_MAX_CELL_X: int = 15
const MAP_MIN_CELL_Y: int = -12
const MAP_MAX_CELL_Y: int = 11

# Quarter-based land expansion pricing (1st quarter owned on Day 1; 2nd -> 4th quarter increase in price)
# Quadrants: Q1 (Left Bottom) -> Q2 (Right Bottom) -> Q3 (Left Top) -> Q4 (Right Top)
const QUARTER_PRICES: Array[int] = [0, 100, 200, 300]
const QUARTER_NAMES: Array[String] = [
	"Quarter 1 (Left Bottom)",
	"Quarter 2 (Right Bottom)",
	"Quarter 3 (Left Top)",
	"Quarter 4 (Right Top)",
]

const FACILITY_TEMPLATES := {
	"cabin": {
		"facility_id": "cabin",
		"display_name": "Cabin",
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 0,
		"base_cycle_time": 7.0,
		"base_payout": 30,
		"cost": 40,
		"unlock_day": 1,
		"preferred_species": ["Cheviot", "Jacob", "Romney"],
		"description": "Gains +$30 / visit (7.0s)\nCost: $40",
		"combo_title": "Combo: Peace & Quiet",
		"combo_desc": "-$10 payout for each other Cabin nearby.\nKeep Cabins spread apart!",
		"flavor_text": "\"Comes with a fluffy hay mattress and 0% wolf-proof locks.\"",
	},
	"restaurant": {
		"facility_id": "restaurant",
		"display_name": "Restaurant",
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 7,
		"base_cycle_time": 4.5,
		"base_payout": 20,
		"cost": 50,
		"unlock_day": 1,
		"preferred_species": ["Suffolk", "Dorper", "Texel"],
		"description": "Gains +$20 / visit (4.5s)\nCost: $50",
		"combo_title": "Combo: Bed & Breakfast",
		"combo_desc": "+$10 payout for each nearby Cabin\n(up to +$30 max from 3 Cabins).",
		"flavor_text": "\"Today's special: Pan-seared clover with dandelion sauce.\"",
	},
	"wool_salon": {
		"facility_id": "wool_salon",
		"display_name": "Wool Salon",
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 13,
		"base_cycle_time": 9.5,
		"base_payout": 55,
		"cost": 75,
		"unlock_day": 2,
		"preferred_species": ["Merino", "Shetland"],
		"description": "Gains +$55 / visit (9.5s)\nCost: $75 • Unlocks Day 2",
		"combo_title": "Combo: Dinner & Style",
		"combo_desc": "+$15 payout when placed near a\nRestaurant or Bakery.",
		"flavor_text": "\"From frizzy pasture fleece to runway curls in one snip!\"",
	},
	"bakery": {
		"facility_id": "bakery",
		"display_name": "Bakery",
		"sheet_path": "res://assets/PhaseII_Map/Buildings2.png",
		"building_row": 1,
		"base_cycle_time": 5.5,
		"base_payout": 35,
		"cost": 65,
		"unlock_day": 3,
		"preferred_species": ["Cheviot", "Romney", "Suffolk"],
		"description": "Gains +$35 / visit (5.5s)\nCost: $65 • Unlocks Day 3",
		"combo_title": "Combo: Sweet Aroma",
		"combo_desc": "+$10 payout for each different\nfacility type nearby (up to +$30).",
		"flavor_text": "\"Fresh oat muffins! Please stop eating the paper wrappers.\"",
	},
	"gift_shop": {
		"facility_id": "gift_shop",
		"display_name": "Gift Shop",
		"sheet_path": "res://assets/PhaseII_Map/Buildings2.png",
		"building_row": 0,
		"base_cycle_time": 6.5,
		"base_payout": 50,
		"cost": 90,
		"unlock_day": 4,
		"preferred_species": ["Dorper", "Texel", "Jacob"],
		"description": "Gains +$50 / visit (6.5s)\nCost: $90 • Unlocks Day 4",
		"combo_title": "Combo: Tourist Trap",
		"combo_desc": "+$20 payout if placed near the\nMain Building or Clock Tower.",
		"flavor_text": "\"Selling 'I Survived Sheep Hi Resort' mugs at a 400% markup.\"",
	},
	"clock_tower": {
		"facility_id": "clock_tower",
		"display_name": "Clock Tower",
		"sheet_path": "res://assets/PhaseII_Map/Buildings2.png",
		"building_row": 14,
		"base_cycle_time": 8.5,
		"base_payout": 75,
		"cost": 120,
		"unlock_day": 5,
		"preferred_species": ["Shetland", "Merino", "Jacob"],
		"description": "Gains +$75 / visit (8.5s)\nCost: $120 • Unlocks Day 5",
		"combo_title": "Combo: Grand Landmark",
		"combo_desc": "Boosts ALL nearby facilities by +$10\nand gains +$5 per neighbor!",
		"flavor_text": "\"Chimes on the hour—unless a sheep gets stuck in the gears.\"",
	},
	"jail": {
		"facility_id": "jail",
		"display_name": "Jail",
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 11,
		"base_cycle_time": 3.5,
		"base_payout": 0,
		"cost": 50,
		"unlock_day": 1,
		"preferred_species": [],
		"description": "Screens & deports wolves (3.5s)",
		"combo_title": "Security Post",
		"combo_desc": "Drag suspect wolves here during Rush Hour.",
		"flavor_text": "\"Reinforced iron bars. Surprisingly cozy!\"",
	},
}

# Day 1 starting facilities: Main Building at bottom of cross pathway,
# Cabin at top, Restaurant on left, Jail on right.
const DEFAULT_FACILITY_INSTANCES := [
	{
		"name": "MainBuilding",
		"facility_id": "main_building",
		"display_name": "Main Building",
		"position": Vector2(-240, 328),
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 8,
		"base_cycle_time": 0.0,
		"base_payout": 0,
	},
	{
		"name": "CabinFacility",
		"facility_id": "cabin",
		"display_name": "Cabin",
		"position": Vector2(-240, 88),
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 0,
		"base_cycle_time": 7.0,
		"base_payout": 30,
	},
	{
		"name": "CloverMeadow",
		"facility_id": "restaurant",
		"display_name": "Restaurant",
		"position": Vector2(-350, 176),
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 7,
		"base_cycle_time": 4.5,
		"base_payout": 20,
	},
	{
		"name": "JailFacility",
		"facility_id": "jail",
		"display_name": "Jail",
		"position": Vector2(-130, 176),
		"sheet_path": "res://assets/PhaseII_Map/Buildings1.png",
		"building_row": 11,
		"base_cycle_time": 3.5,
		"base_payout": 0,
	},
]

const DEFAULT_FACILITY_POSITIONS := {
	"MainBuilding": Vector2(-240, 256),
	"CabinFacility": Vector2(-240, 88),
	"Cabin": Vector2(-240, 88),
	"CloverMeadow": Vector2(-350, 176),
	"ThermalMudBath": Vector2(-240, 88),
	"Restaurant": Vector2(-350, 176),
	"Jail": Vector2(-130, 176),
	"JailFacility": Vector2(-130, 176),
}

var resort_layout: Dictionary = {}
var path_cell_lookup: Dictionary = {}
var land_cell_lookup: Dictionary = {}
var is_layout_edit_mode: bool = false
var returned_from_layout_editor: bool = false
var show_resort_sheep_names: bool = true
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

func init_default_layout(force_reset: bool = false) -> void:
	if force_reset or resort_layout.is_empty():
		var paths: Array = _make_default_cross_pathways()
		var land: Array = _make_default_starting_land()
		resort_layout.clear()
		save_resort_layout(DEFAULT_FACILITY_POSITIONS.duplicate(), paths, DEFAULT_FACILITY_INSTANCES.duplicate(true), land)

func _make_default_cross_pathways() -> Array:
	var paths: Array = []
	# Horizontal arm of cross pathway in Q1 (Left Bottom) connecting Restaurant to Jail
	for x in range(-12, -3):
		paths.append(Vector2i(x, 5))
	# Vertical arm of cross pathway connecting Cabin (top) to Main Building (bottom)
	# Ends at y = 7 so the Main Building sits at the very end of the path without sticking out below
	for y in range(2, 8):
		if y != 5:
			paths.append(Vector2i(-8, y))
	return paths

func _make_default_starting_land() -> Array:
	return get_cells_for_quarter(1)

func save_resort_layout(fac_positions: Dictionary, paths: Array, fac_instances: Array = [], land_cells: Array = []) -> void:
	var instances_copy: Array = []
	if not fac_instances.is_empty():
		instances_copy = fac_instances.duplicate(true)
	elif resort_layout.has("facility_instances"):
		instances_copy = resort_layout["facility_instances"].duplicate(true)
	else:
		instances_copy = DEFAULT_FACILITY_INSTANCES.duplicate(true)

	var land_copy: Array = []
	if not land_cells.is_empty():
		land_copy = land_cells.duplicate()
	elif resort_layout.has("land_cells") and not resort_layout["land_cells"].is_empty():
		land_copy = resort_layout["land_cells"].duplicate()
	else:
		land_copy = _make_default_starting_land()

	var stored_copy: Dictionary = {}
	if resort_layout.has("stored_facilities") and resort_layout["stored_facilities"] is Dictionary:
		stored_copy = resort_layout["stored_facilities"].duplicate(true)

	resort_layout = {
		"facilities": fac_positions.duplicate(),
		"pathways": paths.duplicate(),
		"facility_instances": instances_copy,
		"land_cells": land_copy,
		"stored_facilities": stored_copy,
	}
	path_cell_lookup.clear()
	for cell in paths:
		if cell is Vector2i:
			path_cell_lookup[cell] = true

	land_cell_lookup.clear()
	for lcell in land_copy:
		if lcell is Vector2i:
			land_cell_lookup[lcell] = true

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

func is_land_cell_unlocked(cell: Vector2i) -> bool:
	return land_cell_lookup.has(cell)

func is_world_pos_on_land(world_pos: Vector2) -> bool:
	var cell := world_to_path_cell(world_pos)
	return land_cell_lookup.has(cell)

func is_cell_in_map_bounds(cell: Vector2i) -> bool:
	return cell.x >= MAP_MIN_CELL_X and cell.x <= MAP_MAX_CELL_X and cell.y >= MAP_MIN_CELL_Y and cell.y <= MAP_MAX_CELL_Y

func is_facility_pos_on_land(world_pos: Vector2, fac_rect: Rect2 = Rect2(-35, -85, 70, 75)) -> bool:
	# Check that all 4 corners and center of the facility footprint sit on owned land
	var sample_points := [
		world_pos + Vector2(fac_rect.position.x + 8.0, fac_rect.position.y + 8.0),
		world_pos + Vector2(fac_rect.end.x - 8.0, fac_rect.position.y + 8.0),
		world_pos + Vector2(fac_rect.position.x + 8.0, fac_rect.end.y - 8.0),
		world_pos + Vector2(fac_rect.end.x - 8.0, fac_rect.end.y - 8.0),
		world_pos + fac_rect.get_center(),
	]
	for pt in sample_points:
		var c := world_to_path_cell(pt)
		if not land_cell_lookup.has(c):
			return false
	return true

func unlock_land_cell(cell: Vector2i) -> bool:
	if not is_cell_in_map_bounds(cell) or land_cell_lookup.has(cell):
		return false
	land_cell_lookup[cell] = true
	if not resort_layout.has("land_cells"):
		resort_layout["land_cells"] = []
	resort_layout["land_cells"].append(cell)
	return true

## Returns which map quarter (1..4) a cell belongs to, or 0 if out of map bounds.
## Quadrants:
## Quarter 1: Left Bottom (x < 0, y >= 0)
## Quarter 2: Right Bottom (x >= 0, y >= 0)
## Quarter 3: Left Top (x < 0, y < 0)
## Quarter 4: Right Top (x >= 0, y < 0)
func get_quarter_for_cell(cell: Vector2i) -> int:
	if not is_cell_in_map_bounds(cell):
		return 0
	if cell.x < 0:
		return 1 if cell.y >= 0 else 3
	else:
		return 2 if cell.y >= 0 else 4

func get_cells_for_quarter(quarter_idx: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cy in range(MAP_MIN_CELL_Y, MAP_MAX_CELL_Y + 1):
		for cx in range(MAP_MIN_CELL_X, MAP_MAX_CELL_X + 1):
			var c := Vector2i(cx, cy)
			if get_quarter_for_cell(c) == quarter_idx:
				cells.append(c)
	return cells

func is_quarter_unlocked(quarter_idx: int) -> bool:
	var cells := get_cells_for_quarter(quarter_idx)
	if cells.is_empty():
		return false
	return land_cell_lookup.has(cells[0])

func get_unlocked_quarters_count() -> int:
	var count: int = 0
	for q in range(1, 5):
		if is_quarter_unlocked(q):
			count += 1
	return maxi(count, 1)

func get_next_quarter_cost() -> int:
	var unlocked := get_unlocked_quarters_count()
	if unlocked >= 4:
		return 0
	return QUARTER_PRICES[unlocked]

func get_next_locked_quarter() -> int:
	for q in range(2, 5):
		if not is_quarter_unlocked(q):
			return q
	return 0

func unlock_quarter(quarter_idx: int) -> bool:
	if quarter_idx < 1 or quarter_idx > 4 or is_quarter_unlocked(quarter_idx):
		return false
	var cells := get_cells_for_quarter(quarter_idx)
	for c in cells:
		unlock_land_cell(c)
	return true

func get_total_map_cells() -> int:
	return (MAP_MAX_CELL_X - MAP_MIN_CELL_X + 1) * (MAP_MAX_CELL_Y - MAP_MIN_CELL_Y + 1)

func is_facility_unlocked(fac_id: String) -> bool:
	var tmpl: Dictionary = FACILITY_TEMPLATES.get(fac_id, {})
	var unlock_d: int = tmpl.get("unlock_day", 1)
	return current_day >= unlock_d

func get_facility_cost(fac_id: String) -> int:
	var tmpl: Dictionary = FACILITY_TEMPLATES.get(fac_id, {})
	return tmpl.get("cost", BUILDING_COST)

func get_stored_facility_count(fac_id: String) -> int:
	if not resort_layout.has("stored_facilities") or not (resort_layout["stored_facilities"] is Dictionary):
		return 0
	return int(resort_layout["stored_facilities"].get(fac_id, 0))

func add_stored_facility(fac_id: String, delta: int) -> void:
	if not resort_layout.has("stored_facilities") or not (resort_layout["stored_facilities"] is Dictionary):
		resort_layout["stored_facilities"] = {}
	var cur: int = int(resort_layout["stored_facilities"].get(fac_id, 0))
	resort_layout["stored_facilities"][fac_id] = maxi(0, cur + delta)

## Evaluates the Combo Skill payout delta and affected nearby buildings for a facility at `fac_pos`.
## Returns {"bonus": int, "neighbors": Array[Dictionary]} where each neighbor is {"node": Node2D, "delta": int}.
func calculate_facility_combo(fac_id: String, fac_pos: Vector2, all_facilities: Array, ignore_node: Object = null) -> Dictionary:
	var bonus: int = 0
	var neighbors: Array = []
	var nearby_nodes: Array = []

	for other in all_facilities:
		if not is_instance_valid(other) or other == ignore_node:
			continue
		var dist: float = fac_pos.distance_to(other.position)
		if dist <= COMBO_RANGE and dist > 0.01:
			nearby_nodes.append(other)

	# 1. Check nearby Clock Towers buffing this facility (+$10 per Clock Tower)
	if fac_id != "main_building" and fac_id != "jail" and fac_id != "clock_tower":
		for n in nearby_nodes:
			if n.facility_id == "clock_tower":
				bonus += 10
				neighbors.append({"node": n, "delta": 10})

	# 2. Check this facility's own Combo Skill
	match fac_id:
		"cabin":
			# Peace & Quiet: -$10 for each other Cabin nearby
			for n in nearby_nodes:
				if n.facility_id == "cabin":
					bonus -= 10
					neighbors.append({"node": n, "delta": - 10})
		"restaurant":
			# Bed & Breakfast: +$10 for each nearby Cabin (up to 3)
			var cabin_hits: int = 0
			for n in nearby_nodes:
				if n.facility_id == "cabin" and cabin_hits < 3:
					cabin_hits += 1
					bonus += 10
					neighbors.append({"node": n, "delta": 10})
		"wool_salon":
			# Dinner & Style: +$15 if near a Restaurant or Bakery
			var boosted := false
			for n in nearby_nodes:
				if n.facility_id == "restaurant" or n.facility_id == "bakery":
					if not boosted:
						bonus += 15
						boosted = true
					neighbors.append({"node": n, "delta": 15})
		"bakery":
			# Sweet Aroma: +$10 per distinct facility type nearby (max +$30)
			var seen_types := {}
			for n in nearby_nodes:
				var nid: String = n.facility_id
				if nid != "bakery" and nid != "main_building" and nid != "jail":
					if not seen_types.has(nid) and seen_types.size() < 3:
						seen_types[nid] = true
						bonus += 10
						neighbors.append({"node": n, "delta": 10})
		"gift_shop":
			# Tourist Trap: +$20 if near Main Building or Clock Tower
			var trap_boosted := false
			for n in nearby_nodes:
				if n.facility_id == "main_building" or n.facility_id == "clock_tower":
					if not trap_boosted:
						bonus += 20
						trap_boosted = true
					neighbors.append({"node": n, "delta": 20})
		"clock_tower":
			# Grand Landmark: boosts all nearby revenue facilities by +$10 and gains +$5 per neighbor
			var buffed_count: int = 0
			for n in nearby_nodes:
				var nid: String = n.facility_id
				if nid != "main_building" and nid != "jail":
					buffed_count += 1
					neighbors.append({"node": n, "delta": 10})
			bonus += mini(buffed_count, 5) * 5

	return {
		"bonus": bonus,
		"neighbors": neighbors,
	}

func world_to_path_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / PATH_CELL_SIZE)), int(floor(world_pos.y / PATH_CELL_SIZE)))

func path_cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * PATH_CELL_SIZE + PATH_CELL_SIZE * 0.5, cell.y * PATH_CELL_SIZE + PATH_CELL_SIZE * 0.5)

## Computes a waypoint path around facilities (and preferring paved pathways) using AStarGrid2D.
func find_resort_path(from_world: Vector2, to_world: Vector2, facilities: Array, ignore_fac: Node2D = null) -> Array[Vector2]:
	var astar := AStarGrid2D.new()
	var region := Rect2i(
		MAP_MIN_CELL_X,
		MAP_MIN_CELL_Y,
		MAP_MAX_CELL_X - MAP_MIN_CELL_X + 1,
		MAP_MAX_CELL_Y - MAP_MIN_CELL_Y + 1
	)
	astar.region = region
	astar.cell_size = Vector2(PATH_CELL_SIZE, PATH_CELL_SIZE)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	# 1. Weight paved pathway cells lower so sheep naturally prefer walking on paths
	for cy in range(MAP_MIN_CELL_Y, MAP_MAX_CELL_Y + 1):
		for cx in range(MAP_MIN_CELL_X, MAP_MAX_CELL_X + 1):
			var c := Vector2i(cx, cy)
			if path_cell_lookup.has(c):
				astar.set_point_weight_scale(c, 1.0)
			elif land_cell_lookup.has(c):
				astar.set_point_weight_scale(c, 2.2)
			else:
				astar.set_point_solid(c, true)

	# 2. Mark facility sprite footprints as solid obstacles
	for f in facilities:
		if not is_instance_valid(f) or f == ignore_fac:
			continue
		if f is Node2D and f.has_method("get_obstacle_rect"):
			var fn: Node2D = f as Node2D
			var obs_r: Rect2 = fn.call("get_obstacle_rect")
			var world_r := Rect2(fn.global_position + obs_r.position, obs_r.size)
			var min_c := world_to_path_cell(world_r.position + Vector2(4, 4))
			var max_c := world_to_path_cell(world_r.end - Vector2(4, 4))
			for cy in range(min_c.y, max_c.y + 1):
				for cx in range(min_c.x, max_c.x + 1):
					var c := Vector2i(cx, cy)
					if region.has_point(c):
						astar.set_point_solid(c, true)

	var start_cell := world_to_path_cell(from_world)
	var end_cell := world_to_path_cell(to_world)
	start_cell.x = clampi(start_cell.x, MAP_MIN_CELL_X, MAP_MAX_CELL_X)
	start_cell.y = clampi(start_cell.y, MAP_MIN_CELL_Y, MAP_MAX_CELL_Y)
	end_cell.x = clampi(end_cell.x, MAP_MIN_CELL_X, MAP_MAX_CELL_X)
	end_cell.y = clampi(end_cell.y, MAP_MIN_CELL_Y, MAP_MAX_CELL_Y)

	# Ensure start cell and target facility doorway (end cell + approach cell) are walkable
	astar.set_point_solid(start_cell, false)
	astar.set_point_solid(end_cell, false)
	var south_of_end := end_cell + Vector2i(0, 1)
	if region.has_point(south_of_end):
		astar.set_point_solid(south_of_end, false)

	var id_path: Array[Vector2i] = astar.get_id_path(start_cell, end_cell)
	if id_path.is_empty():
		# Fallback if a facility is completely boxed in by other buildings: allow high-cost traversal through obstacles
		for cy in range(MAP_MIN_CELL_Y, MAP_MAX_CELL_Y + 1):
			for cx in range(MAP_MIN_CELL_X, MAP_MAX_CELL_X + 1):
				var c := Vector2i(cx, cy)
				if land_cell_lookup.has(c) and astar.is_point_solid(c):
					astar.set_point_solid(c, false)
					astar.set_point_weight_scale(c, 15.0)
		id_path = astar.get_id_path(start_cell, end_cell)

	var waypoints: Array[Vector2] = []
	if id_path.size() > 1:
		for i in range(1, id_path.size() - 1):
			waypoints.append(path_cell_to_world(id_path[i]))
	waypoints.append(to_world)
	return waypoints

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
