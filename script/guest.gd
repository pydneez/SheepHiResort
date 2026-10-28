class_name Guest
extends Control
## The guest at the desk (scene/guest.tscn). Where this node sits in
## front_desk.tscn is where the guest stands while being served; they walk in
## from enter_x and leave to exit_x (accepted) or back to enter_x (denied).
## The sheep itself is a SheepLook: stacked part pictures (paper doll).

signal right_clicked  # right-click on the guest = compare their real wool colour

@export var enter_x := -560.0
@export var exit_x := 1480.0
@export var hop_height := 14.0

var desk_position: Vector2

@onready var look: SheepLook = %Look

func _ready() -> void:
	desk_position = position
	visible = false
	look.mouse_filter = Control.MOUSE_FILTER_STOP
	look.gui_input.connect(_on_look_input)

func set_look(appearance: Dictionary) -> void:
	look.show_look(appearance.look)
	look.set_flipped(false)
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
	look.set_flipped(not accepted)
	var t := create_tween()
	t.tween_interval(0.6)
	t.tween_property(self, "position:x", exit_x if accepted else enter_x, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(hide)
	get_tree().create_timer(0.6).timeout.connect(_hop.bind(1.3))
	return t

## Little hop while walking, so a still drawing reads as "walking".
func _hop(duration: float) -> void:
	var t := create_tween().set_loops(int(duration / 0.32))
	t.tween_property(self, "position:y", desk_position.y - hop_height, 0.16)
	t.tween_property(self, "position:y", desk_position.y, 0.16)

func _on_look_input(event: InputEvent) -> void:
	if DeskDocument.is_compare_click(event):
		right_clicked.emit()
		look.accept_event()
