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

const PIXEL_SPRITES := [
	"res://assets/sheep_character_pixel/Detective_sheep_pixel.png",
	"res://assets/sheep_character_pixel/Axel_drifter_pixel.png",
	"res://assets/sheep_character_pixel/Babara_sheep_pixel.png",
	"res://assets/sheep_character_pixel/Gambling_sheep_pixel.png",
	"res://assets/sheep_character_pixel/Rapper_Sheep.png",
	"res://assets/sheep_character_pixel/nun_sheep_pixel.png",
	"res://assets/sheep_character_pixel/star_sheep_pixel.png",
]

const SPECIES_PIXEL_MAP := {
	"Merino": "res://assets/sheep_character_pixel/star_sheep_pixel.png",
	"Suffolk": "res://assets/sheep_character_pixel/Detective_sheep_pixel.png",
	"Dorper": "res://assets/sheep_character_pixel/Rapper_Sheep.png",
	"Jacob": "res://assets/sheep_character_pixel/Gambling_sheep_pixel.png",
	"Cheviot": "res://assets/sheep_character_pixel/Axel_drifter_pixel.png",
	"Texel": "res://assets/sheep_character_pixel/nun_sheep_pixel.png",
	"Shetland": "res://assets/sheep_character_pixel/Babara_sheep_pixel.png",
	"Romney": "res://assets/sheep_character_pixel/star_sheep_pixel.png",
}

@export var move_speed: float = 100.0

var guest_data: Dictionary = {}
var is_wolf: bool = false
var species: String = "Merino"
var preferred_facility_id: String = "clover_meadow"

var state: State = State.ENTERING
var target_pos: Vector2 = Vector2.ZERO
var target_facility: Node2D = null
var last_facility: Node2D = null
var wander_timer: float = 0.0

# Mouse hold & pickup variables
var is_holding: bool = false
var hold_progress: float = 0.0

# Node references
@onready var hold_ring: Node2D = $HoldRing if has_node("HoldRing") else null
@onready var visual_root: Node2D = $VisualRoot
@onready var sprite: Sprite2D = $VisualRoot/Sprite2D
@onready var name_label: Label = $VisualRoot/NameLabel
@onready var deport_bar: ProgressBar = $VisualRoot/DeportBar
@onready var tell_label: Label = $VisualRoot/TellLabel

func setup(data: Dictionary) -> void:
	guest_data = data
	is_wolf = data.get("is_wolf", false)
	var truth: Dictionary = data.get("truth", {})
	species = truth.get("species", "Merino")
	preferred_facility_id = GameManager.get_preferred_facility(species)

	# Name label
	var sheep_name: String = truth.get("name", "Sheep")
	name_label.text = sheep_name

	# Pixel art sprite resolution
	var pixel_path := _resolve_pixel_sprite(data)
	if ResourceLoader.exists(pixel_path):
		sprite.texture = load(pixel_path)

	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(0.85, 0.85)

	# Modulate: subtle wolf tell or wool tint
	var app: Dictionary = data.get("appearance", {})
	var tint: Color = app.get("tint", Color.WHITE)
	if is_wolf:
		sprite.modulate = Color(1.0, 0.82, 0.82)
	else:
		sprite.modulate = tint

	deport_bar.visible = false
	tell_label.visible = false

func _resolve_pixel_sprite(data: Dictionary) -> String:
	var app: Dictionary = data.get("appearance", {})
	var orig_path: String = app.get("sprite", "").to_lower()
	if "detective" in orig_path:
		return "res://assets/sheep_character_pixel/Detective_sheep_pixel.png"
	elif "drift" in orig_path:
		return "res://assets/sheep_character_pixel/Axel_drifter_pixel.png"
	elif "robin" in orig_path:
		return "res://assets/sheep_character_pixel/Rapper_Sheep.png"
	elif "wiz" in orig_path:
		return "res://assets/sheep_character_pixel/star_sheep_pixel.png"
	elif "fake" in orig_path:
		return "res://assets/sheep_character_pixel/Gambling_sheep_pixel.png"

	var truth: Dictionary = data.get("truth", {})
	var spec: String = truth.get("species", "")
	if SPECIES_PIXEL_MAP.has(spec):
		return SPECIES_PIXEL_MAP[spec]

	var guest_name: String = truth.get("name", "Sheep")
	var idx := absi(guest_name.hash()) % PIXEL_SPRITES.size()
	return PIXEL_SPRITES[idx]

func _ready() -> void:
	deport_bar.visible = false
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

	match state:
		State.ENTERING:
			_move_towards(target_pos, delta)
			if global_position.distance_to(target_pos) < 15.0:
				state = State.SEEKING_FACILITY
				guest_ready_for_facility.emit(self)

		State.SEEKING_FACILITY:
			if is_instance_valid(target_facility):
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
				state = State.SEEKING_FACILITY
				guest_ready_for_facility.emit(self)

		State.EXITING:
			_move_towards(target_pos, delta)
			if global_position.distance_to(target_pos) < 20.0:
				queue_free()

func _move_towards(dest: Vector2, _delta: float) -> void:
	var dir := (dest - global_position).normalized()
	var on_path := GameManager.is_world_pos_on_path(global_position)
	var speed := move_speed * 1.45 if on_path else move_speed
	velocity = dir * speed
	move_and_slide()
	if dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0
	var bob_freq := 0.022 if on_path else 0.015
	visual_root.position.y = sin(Time.get_ticks_msec() * bob_freq) * 2.0

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
	_pick_wander_target()

func _pick_wander_target() -> void:
	# Prefer nearby pathways if available, or nearby open ground
	var nearby_paths: Array = []
	var cur_cell := GameManager.world_to_path_cell(global_position)
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := cur_cell + Vector2i(dx, dy)
			if GameManager.path_cell_lookup.has(c):
				nearby_paths.append(GameManager.path_cell_to_world(c))
	
	if not nearby_paths.is_empty() and randf() < 0.7:
		target_pos = nearby_paths.pick_random() + Vector2(randf_range(-6, 6), randf_range(-6, 6))
	else:
		target_pos = global_position + Vector2(randf_range(-90, 90), randf_range(-60, 60))

func on_service_finished() -> void:
	# Emerge from the facility entrance door
	if is_instance_valid(last_facility):
		global_position = last_facility.global_position + Vector2(0, -6)
	
	visual_root.visible = true
	visual_root.modulate.a = 0.0
	visual_root.scale = Vector2(0.5, 0.5)
	
	var step_out_pos := global_position + Vector2(randf_range(-16, 16), 28)
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

func _on_hold_ring_draw() -> void:
	if hold_progress <= 0.0 or not is_instance_valid(hold_ring):
		return
	var r: float = 21.0
	var center := Vector2(0, 4)
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

func _handle_hold_progress(delta: float) -> void:
	if is_holding:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			is_holding = false
		else:
			var mouse_dist := global_position.distance_to(get_global_mouse_position())
			# Held inside circle hitbox?
			if mouse_dist <= HITBOX_RADIUS + 4.0:
				hold_progress = minf(hold_progress + delta * CHARGE_SPEED, 1.0)
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
		if hold_progress > 0.0:
			hold_ring.visible = true
			hold_ring.queue_redraw()
		else:
			hold_ring.visible = false

func _pick_up() -> void:
	state = State.PICKED_UP
	is_holding = false
	hold_progress = 0.0
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

func _drop_sheep() -> void:
	z_index = 0
	visual_root.scale = Vector2(0.85, 0.85)
	visual_root.rotation_degrees = 0.0

	# Check if dropped onto Jail facility
	var jails := get_tree().get_nodes_in_group("jail")
	for jail in jails:
		if is_instance_valid(jail) and jail is Facility and jail.is_point_inside(global_position):
			if jail.process_deportation(self):
				return

	# Dropped onto pasture / pathway: bounce and resume wandering
	var bounce := create_tween()
	bounce.tween_property(visual_root, "scale", Vector2(1.05, 0.7), 0.08)
	bounce.tween_property(visual_root, "scale", Vector2(0.85, 0.85), 0.12)

	wander_for(randf_range(2.0, 4.0))

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	# Inside a facility or exiting? Cannot pick up
	if state == State.IN_FACILITY or state == State.EXITING:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and state != State.PICKED_UP:
			is_holding = true
			# Starts at 25% as requested
			if hold_progress < 0.25:
				hold_progress = 0.25
			if is_instance_valid(hold_ring):
				hold_ring.visible = true
				hold_ring.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if state == State.PICKED_UP:
			_drop_sheep()
		else:
			is_holding = false
