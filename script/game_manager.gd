extends Node
## Global game manager handling cross-phase progression, economic ledger,
## and configuration between the Front Desk (Phase 1) and Resort (Phase 2).

## Set to true to enable the full Phase 1 -> Phase 2 loop.
## Set to false for the standalone Phase 1 course demo.
var ENABLE_PHASE_2: bool = true

# Run progression
var current_day: int = 1
var money: int = 150
var reputation: int = 70
var residents: int = 0
var wolves_admitted_total: int = 0
var guest_book: Array = []

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
	"Cheviot": "main_building",
	"Jacob": "main_building",
	"Texel": "restaurant",
	"Romney": "main_building",
}

# Resort Layout & Pathway Planning (Phase 3 Desk Tool)
const PATH_CELL_SIZE: float = 32.0
const BUILDING_COST: int = 50

const FACILITY_TEMPLATES := {
	"restaurant": {
		"facility_id": "restaurant",
		"display_name": "Restaurant",
		"base_cycle_time": 4.5,
		"base_payout": 15,
		"building_row": 10,
		"cost": BUILDING_COST,
	},
	"main_building": {
		"facility_id": "main_building",
		"display_name": "Main Building",
		"base_cycle_time": 7.5,
		"base_payout": 35,
		"building_row": 8,
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
		"building_row": 7,
		"cost": BUILDING_COST,
	},
}

const DEFAULT_FACILITY_INSTANCES := [
	{
		"name": "CloverMeadow",
		"facility_id": "restaurant",
		"display_name": "Restaurant",
		"position": Vector2(-260, -90),
		"building_row": 10,
		"base_cycle_time": 4.5,
		"base_payout": 15,
	},
	{
		"name": "ThermalMudBath",
		"facility_id": "main_building",
		"display_name": "Main Building",
		"position": Vector2(0, -170),
		"building_row": 8,
		"base_cycle_time": 7.5,
		"base_payout": 35,
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
		"building_row": 7,
		"base_cycle_time": 3.5,
		"base_payout": 0,
	},
]

const DEFAULT_FACILITY_POSITIONS := {
	"CloverMeadow": Vector2(-260, -90),
	"ThermalMudBath": Vector2(0, -170),
	"ShearingBoutique": Vector2(260, -90),
	"Restaurant": Vector2(-260, -90),
	"MainBuilding": Vector2(0, -170),
	"WoolSalon": Vector2(260, -90),
	"Jail": Vector2(-310, 110),
	"JailFacility": Vector2(-310, 110),
}

var resort_layout: Dictionary = {}
var path_cell_lookup: Dictionary = {}
var is_layout_edit_mode: bool = false

func _ready() -> void:
	init_default_layout()

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

