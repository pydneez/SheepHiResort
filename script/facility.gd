class_name Facility
extends Area2D
## Base resort facility handling guest occupation, payouts, wolf sabotage,
## and active spam-to-repair mechanics.

signal payout_earned(amount: int, facility_name: String)
signal facility_broken(facility_name: String)
signal facility_fixed(facility_name: String)
signal tip_bubble_requested(spawn_pos: Vector2, bonus: int)
signal innocent_jailed(guest: Node2D)

@export var facility_id: String = "restaurant"
@export var display_name: String = "Restaurant"
@export var base_cycle_time: float = 5.0
@export var base_payout: int = 15
@export var max_occupants: int = 2
@export var preferred_species: Array[String] = ["Suffolk", "Dorper"]
@export var max_repair_time: float = 15.0

@export_group("Building Appearance")
@export var building_texture: Texture2D
@export var building_row: int = 8 # Row in 15x15 sheet (e.g. 8=Main Building, 7=Restaurant, 13=Wool Salon)
@export var anim_fps: float = 6.0 # Animation speed in frames per second
@export var auto_animate: bool = true # Continuously cycle 15 columns

var is_broken: bool = false
var repair_timer: float = 0.0
var service_timer: float = 0.0
var anim_timer: float = 0.0
var occupants: Array = [] # Array of ResortGuest instances

# Visual node references
@onready var visual_root: Node2D = $VisualRoot
@onready var building_sprite: Sprite2D = $VisualRoot/Buildings1 if has_node("VisualRoot/Buildings1") else null
@onready var name_label: Label = $VisualRoot/NameLabel
@onready var status_label: Label = $VisualRoot/StatusLabel
@onready var progress_bar: ProgressBar = $VisualRoot/ProgressBar
@onready var repair_panel: Control = $VisualRoot/RepairPanel
@onready var repair_time_label: Label = $VisualRoot/RepairPanel/RepairTimeLabel
@onready var slot_marker: Marker2D = $SlotMarker

const BROKEN_SPRITE_SHADER_CODE := """
shader_type canvas_item;
uniform float broken_tint : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (broken_tint > 0.01 && tex.a > 0.01) {
		float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
		vec3 red_col = mix(tex.rgb * vec3(1.15, 0.32, 0.32), vec3(0.95, 0.18, 0.18) * (0.45 + lum * 0.65), 0.65);
		COLOR = vec4(mix(tex.rgb, red_col, broken_tint), tex.a);
	} else {
		COLOR = tex;
	}
}
"""

var _broken_shader_mat: ShaderMaterial = null
var _jail_sub_timers: Array[float] = []
static var _sprite_bbox_cache: Dictionary = {}
var _computed_selection_rect: Rect2 = Rect2()

func get_jail_capacity() -> int:
	if is_instance_valid(GameManager) and GameManager.has_method("get_jail_max_occupants"):
		return GameManager.get_jail_max_occupants()
	return max_occupants

func get_repair_click_seconds() -> float:
	if is_instance_valid(GameManager) and GameManager.has_method("get_repair_click_seconds"):
		return GameManager.get_repair_click_seconds()
	return 1.5

func _ready() -> void:
	add_to_group("facilities")
	name_label.text = display_name
	name_label.visible = not GameManager.is_layout_edit_mode
	status_label.visible = not GameManager.is_layout_edit_mode
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	repair_panel.visible = false
	repair_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(repair_time_label):
		repair_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var warn: ColorRect = repair_panel.get_node_or_null("WarningOverlay")
	if is_instance_valid(warn):
		warn.visible = false
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.max_value = base_cycle_time
	progress_bar.value = 0.0
	progress_bar.visible = false
	_init_building_sprite()
	update_bounds_and_collision()
	if facility_id == "jail":
		add_to_group("jail")
		max_occupants = get_jail_capacity()
	elif facility_id == "main_building":
		add_to_group("main_building")
		max_occupants = 0
		status_label.visible = false
	_update_status()

static var _shared_broken_shader: Shader = null

func _init_building_sprite() -> void:
	if is_instance_valid(building_sprite):
		if building_texture:
			building_sprite.texture = building_texture
		building_sprite.hframes = 15
		building_sprite.vframes = 15
		building_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		building_sprite.frame_coords = Vector2i(0, building_row)
		if _shared_broken_shader == null:
			_shared_broken_shader = Shader.new()
			_shared_broken_shader.code = BROKEN_SPRITE_SHADER_CODE
		_broken_shader_mat = ShaderMaterial.new()
		_broken_shader_mat.shader = _shared_broken_shader
		_broken_shader_mat.set_shader_parameter("broken_tint", 1.0 if is_broken else 0.0)
		building_sprite.material = _broken_shader_mat

func set_building_row(row_idx: int) -> void:
	building_row = clampi(row_idx, 0, 14)
	if is_instance_valid(building_sprite):
		building_sprite.frame_coords.y = building_row
	update_bounds_and_collision()

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
		repair_time_label.text = "TAP TO REPAIR!\n(%.1fs)" % repair_timer
		if repair_timer <= 0.0:
			complete_repair()
		return

	# Handle Jail interrogation / screening
	if facility_id == "jail":
		var cap: int = get_jail_capacity()
		max_occupants = cap
		if not occupants.is_empty():
			service_timer += delta
			for i in range(_jail_sub_timers.size()):
				_jail_sub_timers[i] += delta
			progress_bar.visible = true
			progress_bar.max_value = base_cycle_time
			progress_bar.value = service_timer
			status_label.text = "Screening (%d/%d)... (%.1fs)" % [occupants.size(), cap, maxf(base_cycle_time - service_timer, 0.0)]
			status_label.modulate = Color(1.0, 0.75, 0.3)
			while not occupants.is_empty() and service_timer >= base_cycle_time:
				_finish_jail_screening()
		else:
			service_timer = 0.0
			_jail_sub_timers.clear()
			progress_bar.visible = false
			progress_bar.value = 0.0
		return

	# Handle regular guest servicing
	if not occupants.is_empty():
		service_timer += delta
		var eff_cycle: float = get_effective_cycle_time()
		progress_bar.visible = true
		progress_bar.max_value = eff_cycle
		progress_bar.value = service_timer
		if service_timer >= eff_cycle:
			_complete_service()
	else:
		service_timer = 0.0
		progress_bar.visible = false
		progress_bar.value = 0.0

func get_effective_cycle_time() -> float:
	if facility_id == "jail" or facility_id == "main_building":
		return base_cycle_time
	return maxf(0.5, base_cycle_time * GameManager.get_express_service_multiplier())

func can_accept_guest() -> bool:
	if facility_id == "jail" or facility_id == "main_building":
		return false
	return not is_broken and occupants.size() < max_occupants

func get_slot_position() -> Vector2:
	return global_position + Vector2(randf_range(-6, 6), 22.0)

func enter_guest(guest: Node2D) -> bool:
	if guest.get("is_influencer") or not can_accept_guest():
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
	var all_facs: Array = get_parent().get_children() if get_parent() else []
	var combo_info: Dictionary = GameManager.calculate_facility_combo(facility_id, position, all_facs, self)
	var combo_bonus: int = int(combo_info.get("bonus", 0))
	for guest in departing:
		if not is_instance_valid(guest):
			continue
		# Calculate payout with Combo Skill delta and trait affinity bonus
		var effective_base: int = maxi(2, base_payout + combo_bonus)
		var affinity_bonus: float = 1.5 if preferred_species.has(guest.species) else 1.0
		var payout: int = int(round(effective_base * affinity_bonus))
		payout_earned.emit(payout, display_name)
		if combo_bonus > 0:
			_spawn_floating_text("+$%d (Combo +$%d!)" % [payout, combo_bonus], Color(0.3, 1.0, 0.45), 16)
		elif combo_bonus < 0:
			_spawn_floating_text("+$%d (Combo %d)" % [payout, combo_bonus], Color(1.0, 0.65, 0.3), 16)
		else:
			_spawn_floating_text("+$%d" % payout, Color(0.3, 1.0, 0.3), 16)

		# 35% chance to trigger a Hay Day style TipBubble (halved value)
		if randf() < 0.35:
			tip_bubble_requested.emit(global_position + Vector2(randf_range(-30, 30), -50), maxi(2, int(round(payout * 0.25))))

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
		building_sprite.modulate = Color.WHITE
		if is_instance_valid(_broken_shader_mat):
			_broken_shader_mat.set_shader_parameter("broken_tint", 1.0)
	repair_panel.visible = true
	_spawn_floating_text("OUT OF ORDER! SABOTAGED!", Color(1.0, 0.25, 0.25))
	_update_status()

## Rapid spam-to-repair: each left-click removes 1.5 seconds!
func _on_repair_panel_gui_input(event: InputEvent) -> void:
	if not is_broken or (is_instance_valid(GameManager) and GameManager.is_aiming_freeze_bomb):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		repair_tap()

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not is_broken or (is_instance_valid(GameManager) and GameManager.is_aiming_freeze_bomb):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _is_sheep_at_pos(get_global_mouse_position()):
			return
		repair_tap()

func _unhandled_input(event: InputEvent) -> void:
	if not is_broken or (is_instance_valid(GameManager) and GameManager.is_aiming_freeze_bomb):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos := get_global_mouse_position()
		if _is_sheep_at_pos(mouse_pos):
			return
		if is_point_inside(mouse_pos):
			repair_tap()
			get_viewport().set_input_as_handled()

func _is_sheep_at_pos(world_pos: Vector2) -> bool:
	var guests := get_tree().get_nodes_in_group("resort_guests")
	for g in guests:
		if is_instance_valid(g) and g is ResortGuest:
			var rg: ResortGuest = g as ResortGuest
			if rg.state != ResortGuest.State.IN_FACILITY and rg.state != ResortGuest.State.EXITING:
				if (rg.global_position + Vector2(0, -4)).distance_to(world_pos) <= ResortGuest.HITBOX_RADIUS + 6.0:
					return true
	return false

func repair_tap() -> void:
	if not is_broken:
		return
	var fix_secs: float = get_repair_click_seconds()
	repair_timer = maxf(repair_timer - fix_secs, 0.0)
	_spawn_floating_text("-%.1fs!" % fix_secs, Color(0.2, 0.8, 1.0))
	_squash_and_stretch()
	if repair_timer <= 0.0:
		complete_repair()

func complete_repair() -> void:
	is_broken = false
	repair_timer = 0.0
	repair_panel.visible = false
	if is_instance_valid(building_sprite):
		building_sprite.modulate = Color.WHITE
		if is_instance_valid(_broken_shader_mat):
			_broken_shader_mat.set_shader_parameter("broken_tint", 0.0)
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
		var cap: int = get_jail_capacity()
		max_occupants = cap
		if not occupants.is_empty():
			status_label.text = "Screening (%d/%d)..." % [occupants.size(), cap]
			status_label.modulate = Color(1.0, 0.75, 0.3)
		else:
			status_label.text = "Drop Suspects (0/%d)" % cap
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

func _get_frame_used_rect() -> Rect2i:
	var tex: Texture2D = building_texture
	if tex == null and is_instance_valid(building_sprite):
		tex = building_sprite.texture
	if tex == null:
		return Rect2i()
	var row_clamped: int = clampi(building_row, 0, 14)
	var key: String = "%s:%d" % [tex.resource_path, row_clamped]
	if _sprite_bbox_cache.has(key):
		return _sprite_bbox_cache[key]
	var img: Image = tex.get_image()
	if img == null:
		return Rect2i()
	var fw: int = int(img.get_width() / 15.0)
	var fh: int = int(img.get_height() / 15.0)
	if fw <= 0 or fh <= 0:
		return Rect2i()
	var sub: Image = img.get_region(Rect2i(0, row_clamped * fh, fw, fh))
	var used: Rect2i = sub.get_used_rect()
	_sprite_bbox_cache[key] = used
	return used

func _align_sprite_and_compute_rect() -> void:
	var used: Rect2i = _get_frame_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		_computed_selection_rect = Rect2()
		return
	var tex: Texture2D = building_texture
	if tex == null and is_instance_valid(building_sprite):
		tex = building_sprite.texture
	var fw: float = 150.0
	var fh: float = 150.0
	if tex != null:
		fw = float(tex.get_width()) / 15.0
		fh = float(tex.get_height()) / 15.0

	# Bottom-center of the non-transparent pixels within the centered 150x150 sprite frame
	var local_center_x: float = -fw * 0.5 + float(used.position.x) + float(used.size.x) * 0.5
	var local_bottom_y: float = -fh * 0.5 + float(used.position.y + used.size.y)
	var target_bottom_y: float = -6.0

	if is_instance_valid(building_sprite):
		building_sprite.position = Vector2(roundf(-local_center_x), roundf(target_bottom_y - local_bottom_y))

	var pad: float = 4.0
	var w: float = float(used.size.x)
	var h: float = float(used.size.y)
	_computed_selection_rect = Rect2(
		roundf(-w * 0.5 - pad),
		roundf(target_bottom_y - h - pad),
		roundf(w + pad * 2.0),
		roundf(h + pad * 2.0)
	)

func get_selection_rect() -> Rect2:
	if _computed_selection_rect.size.x > 0.0 and _computed_selection_rect.size.y > 0.0:
		return _computed_selection_rect
	match facility_id:
		"main_building":
			return Rect2(-77, -119, 154, 117)
		"jail":
			return Rect2(-53, -80, 106, 78)
		"cabin":
			return Rect2(-33, -83, 66, 81)
		"restaurant":
			return Rect2(-32, -65, 64, 63)
		"wool_salon":
			return Rect2(-41, -76, 82, 74)
		"bakery":
			return Rect2(-44, -66, 88, 64)
		"gift_shop":
			return Rect2(-51, -68, 102, 66)
		"clock_tower":
			return Rect2(-24, -114, 48, 112)
		_:
			return Rect2(-45, -90, 90, 85)

func get_obstacle_rect() -> Rect2:
	var sel := get_selection_rect()
	# Extend downward slightly so a sheep's head (top ~18px above sheep origin) never clips into the base of the building sprite
	return Rect2(sel.position.x - 4.0, sel.position.y, sel.size.x + 8.0, sel.size.y + 10.0)

func update_bounds_and_collision() -> void:
	_align_sprite_and_compute_rect()
	var rect := get_selection_rect()
	if is_instance_valid(status_label) and is_instance_valid(name_label):
		if facility_id == "main_building":
			name_label.position = Vector2(-110.0, rect.position.y - 22.0)
		else:
			status_label.position = Vector2(-120.0, rect.position.y - 20.0)
			name_label.position = Vector2(-110.0, rect.position.y - 40.0)
	var col_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if is_instance_valid(col_shape):
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = rect.size
		col_shape.shape = rect_shape
		col_shape.position = rect.get_center()

	if is_instance_valid(repair_panel):
		repair_panel.position = rect.position
		repair_panel.size = rect.size
		repair_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var warn: ColorRect = repair_panel.get_node_or_null("WarningOverlay")
		if is_instance_valid(warn):
			warn.visible = false
			warn.size = rect.size
			warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var time_lbl: Label = repair_panel.get_node_or_null("RepairTimeLabel")
		if is_instance_valid(time_lbl):
			time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lbl_w: float = 160.0
			var lbl_h: float = 60.0
			time_lbl.size = Vector2(lbl_w, lbl_h)
			time_lbl.position = Vector2((rect.size.x - lbl_w) * 0.5, (rect.size.y - lbl_h) * 0.5)
			time_lbl.pivot_offset = Vector2(lbl_w * 0.5, lbl_h * 0.5)

func is_point_inside(point: Vector2) -> bool:
	var local_p := to_local(point)
	return get_selection_rect().has_point(local_p)

func process_deportation(guest: ResortGuest) -> bool:
	if not is_instance_valid(guest) or guest.is_influencer:
		return false
	var cap: int = get_jail_capacity()
	max_occupants = cap
	if occupants.size() >= cap:
		_spawn_floating_text("Cell Full (%d/%d)! Screening..." % [occupants.size(), cap], Color(1.0, 0.6, 0.2), 12)
		return false

	var was_empty: bool = occupants.is_empty()
	occupants.append(guest)
	if was_empty:
		service_timer = 0.0
		_jail_sub_timers.clear()
		progress_bar.visible = true
		progress_bar.max_value = base_cycle_time
		progress_bar.value = 0.0
	else:
		_jail_sub_timers.append(0.0)
		progress_bar.visible = true
		progress_bar.max_value = base_cycle_time

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

func update_text_zoom(zoom_val: float) -> void:
	var s: float = clampf(1.0 / zoom_val, 0.55, 1.6)
	var scale_vec := Vector2(s, s)
	if is_instance_valid(name_label):
		name_label.pivot_offset = Vector2(name_label.size.x * 0.5, name_label.size.y * 0.5)
		name_label.scale = scale_vec
	if is_instance_valid(status_label):
		status_label.pivot_offset = Vector2(status_label.size.x * 0.5, status_label.size.y * 0.5)
		status_label.scale = scale_vec
	if is_instance_valid(repair_panel):
		var time_lbl: Label = repair_panel.get_node_or_null("RepairTimeLabel")
		if is_instance_valid(time_lbl):
			time_lbl.pivot_offset = Vector2(time_lbl.size.x * 0.5, time_lbl.size.y * 0.5)
			time_lbl.scale = scale_vec

const GO_TO_JAIL_TEX := preload("res://assets/Ending_Report/Go_to_jail.png")

func _spawn_go_to_jail_popup() -> void:
	var spr := Sprite2D.new()
	spr.texture = GO_TO_JAIL_TEX
	spr.z_index = 80
	spr.position = Vector2(0, -95)
	spr.scale = Vector2(0.02, 0.02)
	add_child(spr)

	var t := create_tween()
	# Pop in with energetic bounce
	t.tween_property(spr, "scale", Vector2(0.11, 0.11), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Float upwards slightly over duration
	t.parallel().tween_property(spr, "position:y", -120.0, 1.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Hold then fade out
	t.tween_interval(0.6)
	t.tween_property(spr, "modulate:a", 0.0, 0.35)
	t.tween_callback(spr.queue_free)

func _finish_jail_screening() -> void:
	if occupants.is_empty():
		service_timer = 0.0
		_jail_sub_timers.clear()
		progress_bar.visible = false
		progress_bar.value = 0.0
		_update_status()
		return

	var guest: ResortGuest = occupants.pop_front()
	if not _jail_sub_timers.is_empty():
		service_timer = _jail_sub_timers.pop_front()
		progress_bar.visible = true
		progress_bar.max_value = base_cycle_time
		progress_bar.value = service_timer
	elif not occupants.is_empty():
		service_timer = 0.0
		progress_bar.visible = true
		progress_bar.max_value = base_cycle_time
		progress_bar.value = 0.0
	else:
		service_timer = 0.0
		progress_bar.visible = false
		progress_bar.value = 0.0

	if not is_instance_valid(guest):
		_update_status()
		return

	if guest.is_wolf:
		# Wolf confirmed: Deport with Go_to_jail stamp!
		_spawn_go_to_jail_popup()
		_shake_building()
		guest.deport()
	else:
		# Innocent sheep: Walks out scot-free, -1 rep citation!
		innocent_jailed.emit(guest)
		_spawn_floating_text("Not a wolf! Innocent released (-1 Rep)", Color(1.0, 0.55, 0.3), 13)
		guest.global_position = global_position + Vector2(0, -6)
		guest.visual_root.visible = true
		guest.visual_root.modulate.a = 0.0
		guest.visual_root.scale = Vector2(0.5, 0.5)
		guest.visual_root.rotation_degrees = 0.0

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
