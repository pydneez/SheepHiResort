class_name Facility
extends Area2D
## Base resort facility handling guest occupation, payouts, wolf sabotage,
## and active spam-to-repair mechanics.

signal payout_earned(amount: int, facility_name: String)
signal facility_broken(facility_name: String)
signal facility_fixed(facility_name: String)
signal tip_bubble_requested(spawn_pos: Vector2, bonus: int)

@export var facility_id: String = "clover_meadow"
@export var display_name: String = "Clover Meadow"
@export var base_cycle_time: float = 5.0
@export var base_payout: int = 15
@export var max_occupants: int = 2
@export var preferred_species: Array[String] = ["Suffolk", "Dorper"]
@export var max_repair_time: float = 15.0

@export_group("Building Appearance")
@export var building_texture: Texture2D
@export var building_row: int = 8       # Row in 15x15 sheet (e.g. 8=Main Building, 7=Restaurant, 13=Wool Salon)
@export var anim_fps: float = 6.0       # Animation speed in frames per second
@export var auto_animate: bool = true   # Continuously cycle 15 columns

var is_broken: bool = false
var repair_timer: float = 0.0
var service_timer: float = 0.0
var anim_timer: float = 0.0
var occupants: Array = []   # Array of ResortGuest instances

# Visual node references
@onready var visual_root: Node2D = $VisualRoot
@onready var building_sprite: Sprite2D = $VisualRoot/Buildings1 if has_node("VisualRoot/Buildings1") else null
@onready var name_label: Label = $VisualRoot/NameLabel
@onready var status_label: Label = $VisualRoot/StatusLabel
@onready var progress_bar: ProgressBar = $VisualRoot/ProgressBar
@onready var repair_panel: Control = $VisualRoot/RepairPanel
@onready var repair_time_label: Label = $VisualRoot/RepairPanel/RepairTimeLabel
@onready var slot_marker: Marker2D = $SlotMarker

func _ready() -> void:
	name_label.text = display_name
	name_label.visible = not GameManager.is_layout_edit_mode
	status_label.visible = not GameManager.is_layout_edit_mode
	repair_panel.visible = false
	repair_panel.gui_input.connect(_on_repair_panel_gui_input)
	progress_bar.max_value = base_cycle_time
	progress_bar.value = 0.0
	progress_bar.visible = false
	_init_building_sprite()
	if facility_id == "jail":
		add_to_group("jail")
		max_occupants = 1
	elif facility_id == "main_building":
		add_to_group("main_building")
		max_occupants = 0
		status_label.visible = false
	_update_status()

func _init_building_sprite() -> void:
	if is_instance_valid(building_sprite):
		if building_texture:
			building_sprite.texture = building_texture
		building_sprite.hframes = 15
		building_sprite.vframes = 15
		building_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		building_sprite.frame_coords = Vector2i(0, building_row)

func set_building_row(row_idx: int) -> void:
	building_row = clampi(row_idx, 0, 14)
	if is_instance_valid(building_sprite):
		building_sprite.frame_coords.y = building_row

func _process(delta: float) -> void:
	# Animate building ONLY when sheep are inside being serviced
	if not occupants.is_empty() and not is_broken and is_instance_valid(building_sprite):
		anim_timer += delta * anim_fps
		var frame_col: int = int(anim_timer) % 15
		building_sprite.frame_coords = Vector2i(frame_col, building_row)
	elif is_instance_valid(building_sprite):
		# Idle: hold at frame 0 (no working smoke/activity)
		building_sprite.frame_coords = Vector2i(0, building_row)


	if is_broken:
		repair_timer = maxf(repair_timer - delta, 0.0)
		repair_time_label.text = "TAP TO REPAIR! (%.1fs)" % repair_timer
		if repair_timer <= 0.0:
			complete_repair()
		return

	# Handle Jail interrogation / screening
	if facility_id == "jail":
		if not occupants.is_empty():
			service_timer += delta
			progress_bar.visible = true
			progress_bar.max_value = base_cycle_time
			progress_bar.value = service_timer
			status_label.text = "Screening... (%.1fs)" % maxf(base_cycle_time - service_timer, 0.0)
			status_label.modulate = Color(1.0, 0.75, 0.3)
			if service_timer >= base_cycle_time:
				_finish_jail_screening()
		else:
			service_timer = 0.0
			progress_bar.visible = false
			progress_bar.value = 0.0
		return

	# Handle regular guest servicing
	if not occupants.is_empty():
		service_timer += delta
		progress_bar.visible = true
		progress_bar.max_value = base_cycle_time
		progress_bar.value = service_timer
		if service_timer >= base_cycle_time:
			_complete_service()
	else:
		service_timer = 0.0
		progress_bar.visible = false
		progress_bar.value = 0.0

func can_accept_guest() -> bool:
	if facility_id == "jail" or facility_id == "main_building":
		return false
	return not is_broken and occupants.size() < max_occupants

func get_slot_position() -> Vector2:
	var door_center: Vector2 = slot_marker.global_position if slot_marker else (global_position + Vector2(0, 15))
	return door_center + Vector2(randf_range(-6, 6), 0)

func enter_guest(guest: Node2D) -> bool:
	if not can_accept_guest():
		return false
	occupants.append(guest)
	_update_status()

	# Check if incoming guest is an undercover wolf
	if guest.is_wolf:
		# Wolf sabotages after a short suspenseful delay (0.8s)
		var t := create_tween()
		t.tween_interval(0.8)
		t.tween_callback(func():
			if is_instance_valid(guest) and occupants.has(guest):
				sabotage(guest)
		)
	return true

func exit_guest(guest: Node2D) -> void:
	occupants.erase(guest)
	_update_status()

func _complete_service() -> void:
	service_timer = 0.0
	progress_bar.visible = false
	progress_bar.value = 0.0
	var departing := occupants.duplicate()
	for guest in departing:
		if not is_instance_valid(guest):
			continue
		# Calculate payout with trait affinity bonus
		var affinity_bonus: float = 1.5 if preferred_species.has(guest.species) else 1.0
		var payout: int = int(round(base_payout * affinity_bonus))
		payout_earned.emit(payout, display_name)
		_spawn_floating_text("+$%d" % payout, Color(0.3, 1.0, 0.3))

		# 35% chance to trigger a Hay Day style TipBubble
		if randf() < 0.35:
			tip_bubble_requested.emit(global_position + Vector2(randf_range(-30, 30), -50), int(round(payout * 0.5)))

		# Release guest
		guest.on_service_finished()
	occupants.clear()
	_update_status()

## Wolf breaks the facility into Out of Order
func sabotage(_wolf: Node2D) -> void:
	is_broken = true
	repair_timer = max_repair_time
	facility_broken.emit(display_name)

	# Kick out occupants
	var departing := occupants.duplicate()
	for g in departing:
		if is_instance_valid(g):
			g.on_service_finished()
	occupants.clear()
	service_timer = 0.0
	progress_bar.value = 0.0

	# Dramatic visual shake and alert
	_shake_building()
	if is_instance_valid(building_sprite):
		building_sprite.modulate = Color(1.0, 0.45, 0.45)
	repair_panel.visible = true
	_spawn_floating_text("OUT OF ORDER! SABOTAGED!", Color(1.0, 0.25, 0.25))
	_update_status()

## Rapid spam-to-repair: each left-click removes 1.5 seconds!
func _on_repair_panel_gui_input(event: InputEvent) -> void:
	if not is_broken:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		repair_tap()

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not is_broken:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		repair_tap()

func _unhandled_input(event: InputEvent) -> void:
	if not is_broken:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos := get_global_mouse_position()
		var building_rect := Rect2(global_position - Vector2(85, 65), Vector2(170, 130))
		if building_rect.has_point(mouse_pos):
			repair_tap()
			get_viewport().set_input_as_handled()

func repair_tap() -> void:
	if not is_broken:
		return
	repair_timer = maxf(repair_timer - 1.5, 0.0)
	_spawn_floating_text("-1.5s!", Color(0.2, 0.8, 1.0))
	_squash_and_stretch()
	if repair_timer <= 0.0:
		complete_repair()

func complete_repair() -> void:
	is_broken = false
	repair_timer = 0.0
	repair_panel.visible = false
	if is_instance_valid(building_sprite):
		building_sprite.modulate = Color.WHITE
	facility_fixed.emit(display_name)
	_spawn_floating_text("REPAIRED!", Color(0.4, 1.0, 0.4))
	_squash_and_stretch()
	_update_status()

func _update_status() -> void:
	if facility_id == "main_building":
		status_label.text = "Entrance Hall"
		status_label.modulate = Color(0.8, 0.85, 1.0)
		return

	if facility_id == "jail":
		if not occupants.is_empty():
			status_label.text = "Screening..."
			status_label.modulate = Color(1.0, 0.75, 0.3)
		else:
			status_label.text = "Drop Suspects Here"
			status_label.modulate = Color(0.95, 0.75, 0.75)
		return

	if is_broken:
		status_label.text = "BROKEN!"
		status_label.modulate = Color(1.0, 0.3, 0.3)
	elif occupants.is_empty():
		status_label.text = "Open (0/%d)" % max_occupants
		status_label.modulate = Color(0.6, 0.9, 0.6)
	else:
		status_label.text = "In Use (%d/%d)" % [occupants.size(), max_occupants]
		status_label.modulate = Color(1.0, 0.85, 0.3)

func is_point_inside(point: Vector2) -> bool:
	var local_p := to_local(point)
	# Check against building boundaries (width ~150, height ~150)
	return absf(local_p.x) <= 80.0 and local_p.y >= -135.0 and local_p.y <= 35.0

func process_deportation(guest: ResortGuest) -> bool:
	if not is_instance_valid(guest):
		return false
	if not occupants.is_empty():
		_spawn_floating_text("Cell Occupied! Screening...", Color(1.0, 0.6, 0.2), 12)
		return false

	occupants.append(guest)
	service_timer = 0.0
	progress_bar.visible = true
	progress_bar.max_value = base_cycle_time
	progress_bar.value = 0.0

	guest.state = ResortGuest.State.IN_FACILITY
	guest.input_pickable = false
	guest.velocity = Vector2.ZERO

	# Animate walking/fading into jail doorway
	var door_pos := global_position + Vector2(0, -6)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(guest, "global_position", door_pos, 0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(guest.visual_root, "modulate:a", 0.0, 0.25)
	t.tween_property(guest.visual_root, "scale", Vector2(0.5, 0.5), 0.3)
	t.chain().tween_callback(func():
		if is_instance_valid(guest):
			guest.visual_root.visible = false
	)
	_update_status()
	return true

func _finish_jail_screening() -> void:
	service_timer = 0.0
	progress_bar.visible = false
	progress_bar.value = 0.0

	if occupants.is_empty():
		_update_status()
		return

	var guest: ResortGuest = occupants.pop_front()
	if not is_instance_valid(guest):
		_update_status()
		return

	if guest.is_wolf:
		# Wolf confirmed: Deport!
		_spawn_floating_text("Wolf have been deported!", Color(1.0, 0.25, 0.25), 15)
		_shake_building()
		guest.deport()
	else:
		# Innocent sheep: Walks out scot-free!
		_spawn_floating_text("Not a wolf! Innocent sheep released!", Color(0.95, 0.85, 0.3), 13)
		guest.global_position = global_position + Vector2(0, -6)
		guest.visual_root.visible = true
		guest.visual_root.modulate.a = 0.0
		guest.visual_root.scale = Vector2(0.5, 0.5)
		guest.visual_root.rotation_degrees = 0.0
		guest.tell_label.text = "Not a wolf! Baaa!"
		guest.tell_label.visible = true

		var exit_step := global_position + Vector2(randf_range(-20, 20), 35)
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(guest, "global_position", exit_step, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(guest.visual_root, "modulate:a", 1.0, 0.3)
		t.tween_property(guest.visual_root, "scale", Vector2(0.85, 0.85), 0.35)
		t.chain().tween_callback(func():
			if is_instance_valid(guest):
				guest.input_pickable = true
				guest.last_facility = self
				guest.wander_for(randf_range(3.0, 5.0))
		)
	_update_status()

func _spawn_floating_text(text: String, color: Color, font_size: int = 13) -> void:
	var float_lbl := Label.new()
	float_lbl.text = text
	float_lbl.modulate = color
	float_lbl.add_theme_font_size_override("font_size", font_size)
	float_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	float_lbl.add_theme_constant_override("outline_size", 4)
	float_lbl.position = Vector2(-100, -85)
	float_lbl.size = Vector2(200, 30)
	float_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(float_lbl)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(float_lbl, "position:y", float_lbl.position.y - 45.0, 1.2).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(float_lbl, "modulate:a", 0.0, 1.2)
	t.finished.connect(float_lbl.queue_free)

func _shake_building() -> void:
	var t := create_tween()
	for i in 6:
		var offset := Vector2(randf_range(-6, 6), randf_range(-4, 4))
		t.tween_property(visual_root, "position", offset, 0.04)
	t.tween_property(visual_root, "position", Vector2.ZERO, 0.05)

func _squash_and_stretch() -> void:
	var t := create_tween()
	t.tween_property(visual_root, "scale", Vector2(1.08, 0.92), 0.08)
	t.tween_property(visual_root, "scale", Vector2(1.0, 1.0), 0.1)
