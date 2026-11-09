class_name ResortGuest
extends CharacterBody2D
## Resort guest entity in Phase 2.
## Uses crisp pixel art sprites, small form factor, autonomous facility seeking,
## and click-and-hold deportation for undercover wolves.

signal wolf_deported(guest: ResortGuest)
signal guest_ready_for_facility(guest: ResortGuest)

enum State { ENTERING, SEEKING_FACILITY, IN_FACILITY, WANDERING, EXITING, PICKED_UP }

const HITBOX_RADIUS: float = 18.0
const CHARGE_SPEED: float = 0.95   # Fills 0.25 to 1.0 in ~0.78s
const DECAY_SPEED: float = 0.85    # Gradually decays if not held or outside hitbox

@export var move_speed: float = 100.0

var guest_data: Dictionary = {}
var is_wolf: bool = false
var is_influencer: bool = false
var species: String = "Merino"
var preferred_facility_id: String = "restaurant"

var state: State = State.ENTERING
var target_pos: Vector2 = Vector2.ZERO
var target_facility: Node2D = null
var last_facility: Node2D = null
var wander_timer: float = 0.0
var nav_waypoints: Array[Vector2] = []
var nav_destination: Vector2 = Vector2.INF
var nav_repath_timer: float = 0.0
var last_checked_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0

# Mouse hold & pickup variables
var is_holding: bool = false
var hold_progress: float = 0.0
var freeze_timer: float = 0.0

# Node references
@onready var hold_ring: Node2D = $HoldRing if has_node("HoldRing") else null
@onready var visual_root: Node2D = $VisualRoot
@onready var sprite: Sprite2D = $VisualRoot/Sprite2D
@onready var name_label: Label = $VisualRoot/NameLabel

func setup(data: Dictionary) -> void:
	guest_data = data
	is_wolf = data.get("is_wolf", false)
	is_influencer = data.get("is_influencer", false)
	var truth: Dictionary = data.get("truth", {})
	species = truth.get("species", "Merino")
	preferred_facility_id = GameManager.get_preferred_facility(species)

	# Name label
	var sheep_name: String = truth.get("name", "Sheep")
	name_label.text = sheep_name
	name_label.visible = GameManager.show_resort_sheep_names

	# The pixel version of the sheep they were at the front desk.
	var pixel := SheepCharacters.shared().pixel_for(data)
	if pixel:
		sprite.texture = pixel

	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(0.85, 0.85)

	# Subtle wolf tell
	sprite.modulate = Color(1.0, 0.82, 0.82) if is_wolf else Color.WHITE

func update_text_zoom(zoom_val: float) -> void:
	var s: float = clampf(1.0 / zoom_val, 0.55, 1.6) * 0.85
	var scale_vec := Vector2(s, s)
	if is_instance_valid(name_label):
		name_label.pivot_offset = Vector2(name_label.size.x * 0.5, name_label.size.y * 0.5)
		name_label.scale = scale_vec

func _ready() -> void:
	add_to_group("resort_guests")
	if is_instance_valid(name_label):
		name_label.pivot_offset = Vector2(name_label.size.x * 0.5, name_label.size.y * 0.5)
		name_label.visible = GameManager.show_resort_sheep_names
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if is_instance_valid(hold_ring):
		hold_ring.draw.connect(_on_hold_ring_draw)
		hold_ring.visible = false

func _physics_process(delta: float) -> void:
	# 1. Carried / Picked up state: follow mouse until released
	if state == State.PICKED_UP:
		velocity = Vector2.ZERO
		global_position = get_global_mouse_position() + Vector2(0, -10)
		visual_root.rotation_degrees = 12.0 + sin(Time.get_ticks_msec() * 0.014) * 4.0
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_drop_sheep()
		return

	# 2. Handle hold progress increase / decay
	_handle_hold_progress(delta)

	# 3. Frozen by Freeze Bomb: stay in place while still pickable
	if freeze_timer > 0.0:
		freeze_timer = maxf(freeze_timer - delta, 0.0)
		velocity = Vector2.ZERO
		_update_freeze_visual()
		if is_instance_valid(hold_ring):
			hold_ring.visible = (hold_progress > 0.0 or freeze_timer > 0.0)
			hold_ring.queue_redraw()
		return

	match state:
		State.ENTERING:
			_move_towards(target_pos, delta)
			if global_position.distance_to(target_pos) < 15.0:
				if is_influencer:
					wander_for(randf_range(3.0, 5.0))
				else:
					state = State.SEEKING_FACILITY
					guest_ready_for_facility.emit(self)

		State.SEEKING_FACILITY:
			if is_influencer:
				wander_for(randf_range(3.0, 5.0))
			elif is_instance_valid(target_facility):
				var slot: Vector2 = target_facility.get_slot_position()
				_move_towards(slot, delta)
				if global_position.distance_to(slot) < 22.0:
					if target_facility.enter_guest(self):
						state = State.IN_FACILITY
						input_pickable = false  # Disable picking while inside facility
						velocity = Vector2.ZERO
						last_facility = target_facility
						_animate_enter_facility(target_facility)
					else:
						target_facility = null
						wander_for(randf_range(2.0, 4.0))
			else:
				wander_for(randf_range(1.5, 3.0))

		State.IN_FACILITY:
			velocity = Vector2.ZERO

		State.WANDERING:
			wander_timer -= delta
			_move_towards(target_pos, delta)
			# If reached waypoint before the wander timer expires, pick another waypoint to keep moving
			if global_position.distance_to(target_pos) < 20.0 and wander_timer > 0.0:
				_pick_wander_target()
			elif wander_timer <= 0.0:
				if is_influencer:
					wander_for(randf_range(3.0, 5.0))
				else:
					state = State.SEEKING_FACILITY
					guest_ready_for_facility.emit(self)

		State.EXITING:
			_move_towards(target_pos, delta)
			if global_position.distance_to(target_pos) < 20.0:
				queue_free()

func _move_towards(dest: Vector2, delta: float) -> void:
	nav_repath_timer -= delta
	var ignore_fac: Node2D = target_facility if state == State.SEEKING_FACILITY else null

	# 1. Option 3: AStarGrid2D Waypoint Pathfinding around buildings and along paved paths
	if nav_waypoints.is_empty() or nav_destination.distance_to(dest) > 18.0 or nav_repath_timer <= 0.0:
		nav_repath_timer = 0.65
		nav_destination = dest
		if global_position.distance_to(dest) > 24.0:
			var facs: Array = [] if not GameManager.cached_facility_obstacles.is_empty() else get_tree().get_nodes_in_group("facilities")
			nav_waypoints = GameManager.find_resort_path(global_position, dest, facs, ignore_fac)
		else:
			nav_waypoints = [dest]

	while nav_waypoints.size() > 1 and global_position.distance_to(nav_waypoints[0]) < 18.0:
		nav_waypoints.pop_front()

	var current_step: Vector2 = nav_waypoints[0] if not nav_waypoints.is_empty() else dest
	var dir := (current_step - global_position).normalized()
	var on_path := GameManager.is_world_pos_on_path(global_position)
	var speed := move_speed * 1.45 if on_path else move_speed

	# Check if stuck for any reason while seeking a facility
	if global_position.distance_to(last_checked_pos) < 3.5:
		stuck_timer += delta
	else:
		stuck_timer = maxf(stuck_timer - delta * 2.0, 0.0)
		last_checked_pos = global_position

	if stuck_timer >= 1.5 and state == State.SEEKING_FACILITY:
		stuck_timer = 0.0
		target_facility = null
		wander_for(randf_range(1.5, 3.0))
		return

	velocity = dir * speed
	move_and_slide()
	if dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0
	var bob_freq := 0.022 if on_path else 0.015
	visual_root.position.y = sin(Time.get_ticks_msec() * bob_freq) * 2.0

func _get_blocking_facility_at(pt: Vector2, margin: float = 8.0, ignore_fac: Node2D = null) -> Node2D:
	if not GameManager.cached_facility_obstacles.is_empty():
		for entry in GameManager.cached_facility_obstacles:
			var fn: Node2D = entry.get("node")
			if not is_instance_valid(fn) or fn == ignore_fac:
				continue
			var world_r: Rect2 = entry.get("world_rect", Rect2()).grow(margin)
			if world_r.has_point(pt):
				return fn
		return null
	var facs := get_tree().get_nodes_in_group("facilities")
	for f in facs:
		if not is_instance_valid(f) or f == ignore_fac:
			continue
		if f is Node2D and f.has_method("get_obstacle_rect"):
			var fn: Node2D = f as Node2D
			var r: Rect2 = fn.call("get_obstacle_rect").grow(margin)
			var world_r := Rect2(fn.global_position + r.position, r.size)
			if world_r.has_point(pt):
				return fn
	return null

func _is_point_in_any_facility(pt: Vector2, margin: float = 10.0, ignore_fac: Node2D = null) -> bool:
	return is_instance_valid(_get_blocking_facility_at(pt, margin, ignore_fac))

func _animate_enter_facility(fac: Node2D) -> void:
	# Walk into the doorway and fade in
	var door_pos := fac.global_position + Vector2(0, -6)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "global_position", door_pos, 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(visual_root, "modulate:a", 0.0, 0.3)
	t.tween_property(visual_root, "scale", Vector2(0.5, 0.5), 0.35)
	t.chain().tween_callback(func():
		visual_root.visible = false
	)

func wander_for(duration: float) -> void:
	state = State.WANDERING
	input_pickable = true
	wander_timer = duration
	nav_waypoints.clear()
	_pick_wander_target()

func _pick_wander_target() -> void:
	# Prefer nearby pathways if available, or nearby open ground, strictly avoiding building sprites
	var nearby_paths: Array[Vector2] = []
	var cur_cell := GameManager.world_to_path_cell(global_position)
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var c := cur_cell + Vector2i(dx, dy)
			if GameManager.path_cell_lookup.has(c):
				var wp := GameManager.path_cell_to_world(c)
				if not _is_point_in_any_facility(wp, 10.0):
					nearby_paths.append(wp)

	if not nearby_paths.is_empty() and randf() < 0.75:
		var cand: Vector2 = nearby_paths.pick_random() + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		if not _is_point_in_any_facility(cand, 6.0):
			target_pos = cand
			return

	var nearby_land: Array[Vector2] = []
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var c := cur_cell + Vector2i(dx, dy)
			if GameManager.is_land_cell_unlocked(c):
				var wp := GameManager.path_cell_to_world(c)
				if not _is_point_in_any_facility(wp, 10.0):
					nearby_land.append(wp)
	if not nearby_land.is_empty():
		var cand: Vector2 = nearby_land.pick_random() + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		if not _is_point_in_any_facility(cand, 6.0):
			target_pos = cand
			return
		target_pos = nearby_land.pick_random()
	else:
		target_pos = global_position + Vector2(0, 28)

func on_service_finished() -> void:
	# Emerge from the facility entrance door
	if is_instance_valid(last_facility):
		global_position = last_facility.global_position + Vector2(0, -6)

	visual_root.visible = true
	visual_root.modulate.a = 0.0
	visual_root.scale = Vector2(0.5, 0.5)

	var step_out_pos := global_position + Vector2(randf_range(-14, 14), 22)
	step_out_pos = GameManager.clamp_to_owned_land(step_out_pos)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "global_position", step_out_pos, 0.35).set_trans(Tween.TRANS_SINE)
	t.tween_property(visual_root, "modulate:a", 1.0, 0.3)
	t.tween_property(visual_root, "scale", Vector2(1.0, 1.0), 0.35)
	t.chain().tween_callback(func():
		input_pickable = true
		target_facility = null
		wander_for(randf_range(3.0, 5.0))
	)

func deport() -> void:
	wolf_deported.emit(self)
	queue_free()

# =============================================================================
# Circle Progress Hold & Pick-Up System (Underneath Sheep Model)
# =============================================================================

func is_frozen() -> bool:
	return freeze_timer > 0.0

func apply_freeze(duration: float) -> void:
	if state == State.IN_FACILITY or state == State.EXITING:
		return
	freeze_timer = maxf(freeze_timer, duration)
	velocity = Vector2.ZERO
	_update_freeze_visual()
	if is_instance_valid(hold_ring):
		hold_ring.visible = true
		hold_ring.queue_redraw()

func _update_freeze_visual() -> void:
	if not is_instance_valid(sprite):
		return
	if freeze_timer > 0.0 and state != State.PICKED_UP:
		sprite.modulate = Color(0.45, 0.88, 1.0, 1.0)
	else:
		sprite.modulate = Color(1.0, 0.82, 0.82) if is_wolf else Color.WHITE

func _on_hold_ring_draw() -> void:
	if (hold_progress <= 0.0 and freeze_timer <= 0.0) or not is_instance_valid(hold_ring):
		return
	var r: float = 21.0
	var center := Vector2(0, 4)
	if freeze_timer > 0.0:
		# Icy ground circle & frost ring under frozen sheep
		hold_ring.draw_circle(center, r + 3.0, Color(0.35, 0.85, 1.0, 0.28))
		hold_ring.draw_arc(center, r + 2.0, 0, TAU, 32, Color(0.55, 0.95, 1.0, 0.85), 2.5, true)
	if hold_progress <= 0.0:
		return
	# Soft ground shadow ring under model
	hold_ring.draw_circle(center, r + 2.0, Color(0.0, 0.0, 0.0, 0.22 * hold_progress))
	# Background track ring
	hold_ring.draw_arc(center, r, 0, TAU, 32, Color(0.12, 0.16, 0.22, 0.7), 3.5, true)
	# Active fill arc (starting at -PI/2 = top 12 o'clock, clockwise)
	var start_angle := -PI * 0.5
	var end_angle := start_angle + hold_progress * TAU
	# Color shift: amber gold at 25% -> bright emerald/cyan at 100%
	var ring_color: Color = Color(1.0, 0.78, 0.2).lerp(Color(0.2, 1.0, 0.55), clampf((hold_progress - 0.25) / 0.75, 0.0, 1.0))
	hold_ring.draw_arc(center, r, start_angle, end_angle, 32, ring_color, 3.5, true)

func get_effective_hold_duration() -> float:
	var base_duration: float = 0.75 / CHARGE_SPEED
	var reduction: float = 0.0
	if is_instance_valid(GameManager) and GameManager.has_method("get_force_of_nature_reduction"):
		reduction = GameManager.get_force_of_nature_reduction()
	return maxf(0.18, base_duration - reduction)

func get_effective_charge_speed() -> float:
	return 0.75 / get_effective_hold_duration()

func _handle_hold_progress(delta: float) -> void:
	if is_holding:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_holding = false
		else:
			var mouse_dist := (global_position + Vector2(0, -4)).distance_to(get_global_mouse_position())
			# Held inside circle hitbox?
			if mouse_dist <= HITBOX_RADIUS + 6.0:
				hold_progress = minf(hold_progress + delta * get_effective_charge_speed(), 1.0)
				if hold_progress >= 1.0:
					_pick_up()
					return
			else:
				# Outside hitbox: gradually decrease
				hold_progress = maxf(hold_progress - delta * DECAY_SPEED, 0.0)
	else:
		# Released or not holding: gradually decrease towards 0
		if hold_progress > 0.0:
			hold_progress = maxf(hold_progress - delta * DECAY_SPEED, 0.0)

	# Update visual ring
	if is_instance_valid(hold_ring):
		if hold_progress > 0.0 or freeze_timer > 0.0:
			hold_ring.visible = true
			hold_ring.queue_redraw()
		else:
			hold_ring.visible = false

func _pick_up() -> void:
	SfxManager.play_sfx("Pickup_sheep")
	state = State.PICKED_UP
	is_holding = false
	hold_progress = 0.0
	freeze_timer = 0.0
	_update_freeze_visual()
	if is_instance_valid(hold_ring):
		hold_ring.visible = false

	# While picked up, cannot interact with any facility
	target_facility = null
	z_index = 45 # Render above facilities and ground
	visual_root.scale = Vector2(1.15, 1.15)
	visual_root.rotation_degrees = 12.0

	var squish := create_tween()
	squish.tween_property(visual_root, "scale", Vector2(1.22, 1.08), 0.08)
	squish.tween_property(visual_root, "scale", Vector2(1.15, 1.15), 0.08)

func force_release_on_round_end() -> void:
	is_holding = false
	hold_progress = 0.0
	if is_instance_valid(hold_ring):
		hold_ring.visible = false
	if state == State.PICKED_UP:
		z_index = 0
		visual_root.scale = Vector2(0.85, 0.85)
		visual_root.rotation_degrees = 0.0
		var blocking := _get_blocking_facility_at(global_position, 4.0)
		if is_instance_valid(blocking) and blocking.has_method("get_obstacle_rect"):
			var obs_r: Rect2 = blocking.get_obstacle_rect()
			global_position.y = blocking.global_position.y + obs_r.end.y + 14.0
		global_position = GameManager.clamp_to_owned_land(global_position)
		state = State.WANDERING

func _drop_sheep() -> void:
	SfxManager.play_sfx("Pickup_sheep_drop")
	z_index = 0
	visual_root.scale = Vector2(0.85, 0.85)
	visual_root.rotation_degrees = 0.0

	# Check if dropped onto Jail facility
	var jails := get_tree().get_nodes_in_group("jail")
	for jail in jails:
		if is_instance_valid(jail) and jail is Facility and jail.is_point_inside(global_position):
			if jail.process_deportation(self):
				return

	# Ensure dropped sheep is pushed out in front if dropped over any building sprite
	var blocking := _get_blocking_facility_at(global_position, 4.0)
	if is_instance_valid(blocking) and blocking.has_method("get_obstacle_rect"):
		var obs_r: Rect2 = blocking.get_obstacle_rect()
		global_position.y = blocking.global_position.y + obs_r.end.y + 14.0

	# Dropped onto pasture / pathway: bounce and resume wandering
	var bounce := create_tween()
	bounce.tween_property(visual_root, "scale", Vector2(1.05, 0.7), 0.08)
	bounce.tween_property(visual_root, "scale", Vector2(0.85, 0.85), 0.12)

	wander_for(randf_range(2.0, 4.0))

func _start_holding() -> void:
	if is_influencer:
		return
	is_holding = true
	if hold_progress < 0.25:
		hold_progress = 0.25
	if is_instance_valid(hold_ring):
		hold_ring.visible = true
		hold_ring.queue_redraw()

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if is_instance_valid(GameManager) and GameManager.is_aiming_freeze_bomb:
		return
	# Inside a facility or exiting? Cannot pick up
	if state == State.IN_FACILITY or state == State.EXITING:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and state != State.PICKED_UP:
			_start_holding()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(GameManager) and GameManager.is_aiming_freeze_bomb:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if state == State.IN_FACILITY or state == State.EXITING or state == State.PICKED_UP:
				return
			var mouse_pos := get_global_mouse_position()
			var my_dist := (global_position + Vector2(0, -4)).distance_to(mouse_pos)
			if my_dist <= HITBOX_RADIUS + 6.0:
				# Only start holding if this is the closest valid sheep to the cursor
				var closest_guest: ResortGuest = self
				var closest_dist: float = my_dist
				for g in get_tree().get_nodes_in_group("resort_guests"):
					if is_instance_valid(g) and g is ResortGuest and g != self:
						var other_guest: ResortGuest = g as ResortGuest
						if other_guest.state != State.IN_FACILITY and other_guest.state != State.EXITING and other_guest.state != State.PICKED_UP:
							var d: float = (other_guest.global_position + Vector2(0, -4)).distance_to(mouse_pos)
							if d < closest_dist:
								closest_dist = d
								closest_guest = other_guest
				if closest_guest == self:
					_start_holding()
		else:
			if state == State.PICKED_UP:
				_drop_sheep()
			else:
				is_holding = false
