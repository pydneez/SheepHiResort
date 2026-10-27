class_name Guest
extends Control
## The guest at the desk (scene/guest.tscn). Where this node sits in
## front_desk.tscn is where the guest stands while being served; they walk in
## from enter_x and leave to exit_x (accepted) or back to enter_x (denied).
## Later the paper-doll layers (base, clothes, eyes, hat...) go inside this scene.

signal right_clicked  # right-click on the guest = compare their real wool colour

@export var enter_x := -560.0
@export var exit_x := 1480.0
@export var hop_height := 14.0

var desk_position: Vector2

@onready var body: TextureRect = %Body

func _ready() -> void:
	desk_position = position
	visible = false
	body.gui_input.connect(_on_body_input)

func set_look(appearance: Dictionary) -> void:
	body.texture = load(appearance.sprite)
	body.self_modulate = appearance.tint
	body.flip_h = false
	scale = Vector2.ONE * appearance.scale

## Walk from the left edge to the desk. Returns the tween so callers can chain onto it.
func walk_in() -> Tween:
	position = Vector2(enter_x, desk_position.y)
	visible = true
	var t := create_tween()
	t.tween_property(self, "position:x", desk_position.x, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hop(1.6)
	return t

## Leave: accepted guests go right (into the hotel), denied ones turn back left.
func walk_out(accepted: bool) -> Tween:
	body.flip_h = not accepted
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(self, "position:x", exit_x if accepted else enter_x, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(hide)
	get_tree().create_timer(0.6).timeout.connect(_hop.bind(1.3))
	return t

## Little hop while walking, so a static drawing reads as "walking".
func _hop(duration: float) -> void:
	var t := create_tween().set_loops(int(duration / 0.32))
	t.tween_property(self, "position:y", desk_position.y - hop_height, 0.16)
	t.tween_property(self, "position:y", desk_position.y, 0.16)

func _on_body_input(event: InputEvent) -> void:
	if DeskDocument.is_compare_click(event):
		right_clicked.emit()
		body.accept_event()
