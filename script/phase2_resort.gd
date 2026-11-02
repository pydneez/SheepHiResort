class_name Phase2Resort
extends Node2D
## Phase 2: Resort / Pasture Manager.
## Manages the 60s Rush Hour, guest pathfinding to facilities, active micro-events,
## rapid repairs, wolf deportation, and the end-of-rush ledger.

const RUSH_HOUR_DURATION: float = 60.0
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

var guest_queue: Array = []
var active_guests: Array = []
var facilities: Array = []

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

func _ready() -> void:
	ledger_panel.visible = false
	next_day_button.pressed.connect(_on_next_day_pressed)

	# Apply custom resort layout and pathways
	_apply_resort_layout()
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

	# Prepare guest pool
	if GameManager.admitted_guests.is_empty():
		_generate_fallback_pool()
	else:
		guest_queue = GameManager.admitted_guests.duplicate()

	time_left = RUSH_HOUR_DURATION
	is_active = true
	_refresh_hud()

	# Start spawning queue sequentially
	_spawn_next_guest()

func _init_layout_edit_mode(pathways: PathwaysRenderer) -> void:
	is_active = false
	$UILayer.visible = false
	camera.position = Vector2(80, 50)
	camera.zoom = Vector2(0.85, 0.85)

	var editor = RESORT_LAYOUT_EDITOR.new()
	editor.name = "ResortLayoutEditor"
	add_child(editor)
	editor.setup(self, facilities_container, pathways)

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
	return fac

func _setup_pathways() -> PathwaysRenderer:
	var pathways := PathwaysRenderer.new()
	pathways.name = "PathwaysRenderer"
	$WorldRoot.add_child(pathways)
	$WorldRoot.move_child(pathways, 0)
	return pathways

func _matches_facility_id(fac_id: String, pref_id: String) -> bool:
	if fac_id == pref_id:
		return true
	var aliases := {
		"cabin": ["cabin", "lodge"],
		"lodge": ["cabin", "lodge"],
		"restaurant": ["restaurant", "clover_meadow"],
		"clover_meadow": ["restaurant", "clover_meadow"],
		"main_building": ["main_building", "thermal_mud_bath"],
		"thermal_mud_bath": ["main_building", "thermal_mud_bath"],
		"wool_salon": ["wool_salon", "shearing_boutique"],
		"shearing_boutique": ["wool_salon", "shearing_boutique"],
		"jail": ["jail", "jail_facility"],
		"jail_facility": ["jail", "jail_facility"],
	}
	return aliases.has(fac_id) and aliases[fac_id].has(pref_id)

func _process(delta: float) -> void:
	if not is_active:
		return

	time_left -= delta
	_refresh_hud()

	if time_left <= 0.0:
		time_left = 0.0
		_end_rush_hour()

func _refresh_hud() -> void:
	hud_timer_label.text = "Rush Hour: %02d:%02d" % [int(time_left / 60.0), int(fmod(time_left, 60.0))]
	hud_money_label.text = "Earned: +$%d" % (resort_revenue + resort_tips - resort_damages)
	hud_guests_label.text = "Guests: %d" % active_guests.size()
	hud_wolves_label.text = "Wolves Deported: %d" % wolves_caught

func _spawn_next_guest() -> void:
	if not is_active or guest_queue.is_empty():
		return

	var data: Dictionary = guest_queue.pop_front()
	spawn_guest_from_data(data)

	# Schedule next spawn
	if not guest_queue.is_empty():
		var timer := get_tree().create_timer(1.8)
		timer.timeout.connect(_spawn_next_guest)

func _get_spawn_position() -> Vector2:
	# Spawn from the Main Building if present
	for f in facilities_container.get_children():
		if f is Facility and f.facility_id == "main_building":
			return f.get_slot_position()
	return entrance_marker.global_position

func spawn_guest_from_data(data: Dictionary) -> ResortGuest:
	var guest: ResortGuest = GUEST_SCENE.instantiate()
	guests_container.add_child(guest)
	var spawn_pos := _get_spawn_position()
	guest.global_position = spawn_pos
	guest.setup(data)
	# Step forward out of the doorway onto the walkway
	guest.target_pos = spawn_pos + Vector2(randf_range(-30, 30), 45.0)

	guest.guest_ready_for_facility.connect(_assign_guest_to_facility)
	guest.wolf_deported.connect(_on_wolf_deported)
	active_guests.append(guest)
	_refresh_hud()
	return guest

func _assign_guest_to_facility(guest) -> void:
	if not is_instance_valid(guest):
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
	_refresh_hud()

func _on_facility_broken(_fac_name: String) -> void:
	if not is_active:
		return
	resort_damages += 15
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
	wolves_caught += 1
	active_guests.erase(guest)
	GameManager.wolves_caught_in_resort += 1
	# Award deportation bounty
	resort_tips += 25
	_refresh_hud()

func _end_rush_hour() -> void:
	is_active = false
	
	# Freeze the resort world: stop movement, guest actions, facilities, bubbles, and timers
	$WorldRoot.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Count any wolves that escaped without being deported
	var escaped_wolves := 0
	for g in active_guests:
		if is_instance_valid(g) and g.is_wolf:
			escaped_wolves += 1
	GameManager.wolves_escaped_unharmed = escaped_wolves

	# Update total economy in GameManager
	var net_profit: int = resort_revenue + resort_tips - resort_damages
	GameManager.money += net_profit
	GameManager.phase2_revenue = resort_revenue
	GameManager.phase2_tips = resort_tips
	GameManager.phase2_damages = resort_damages

	# Display End-of-Day Rush Hour Ledger
	var summary: String = "[center][b]RESORT RUSH HOUR COMPLETE![/b][/center]\n\n"
	summary += "• Facility Revenue: [color=#55dd55]+$%d[/color]\n" % resort_revenue
	summary += "• Tip Bubbles & Bounties: [color=#55dd55]+$%d[/color]\n" % resort_tips
	summary += "• Sabotage & Damage Costs: [color=#ff5555]-$%d[/color]\n\n" % resort_damages
	summary += "[b]NET RESORT PROFIT: $%d[/b]\n" % net_profit
	summary += "Total Balance: $%d\n\n" % GameManager.money
	if wolves_caught > 0:
		summary += "[color=#44ff88]★ %d undercover wolves were caught and deported![/color]\n" % wolves_caught
	if escaped_wolves > 0:
		summary += "[color=#ff5555]⚠ %d wolf remained undetected in the resort![/color]\n" % escaped_wolves
	elif wolves_caught == 0:
		summary += "[color=#aaaaaa]Peaceful day. No wolves found.[/color]\n"

	ledger_text.text = summary
	ledger_panel.visible = true

func _on_next_day_pressed() -> void:
	# Advance to next day and return to Front Desk (Phase 1)
	GameManager.current_day += 1
	GameManager.reset_day_pool()
	GameManager.change_scene("res://scene/front_desk.tscn")

func _generate_fallback_pool() -> void:
	# Generates a quick test queue when running Phase 2 directly from editor:
	# real generated guests (so each has its drawn sheep), 1 undercover wolf.
	for i in 6:
		guest_queue.append(GameManager.make_dev_guest(i == 4, i + 1))
