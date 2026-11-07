class_name TipBubble
extends Area2D
## Interactive floating bonus bubble (Hay Day style).
## Pops on left click to grant bonus coins and plays a rewarding bounce animation.

signal bubble_popped(payout: int)

@export var bonus_amount: int = 15
@export var lifetime: float = 6.0

var _age: float = 0.0
var _is_popped: bool = false

@onready var visual_root: Node2D = $VisualRoot
@onready var label: Label = $VisualRoot/Label

const BASE_SCALE := Vector2(0.7, 0.7)

func _ready() -> void:
	label.text = "+$%d" % bonus_amount
	# Entrance pop-in animation
	visual_root.scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(visual_root, "scale", BASE_SCALE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if _is_popped:
		return
	_age += delta
	# Floating bobbing motion
	visual_root.position.y = sin(_age * 4.0) * 5.0

	# Flash and fade when expiring
	if _age >= lifetime - 1.5:
		visual_root.modulate.a = 0.5 + 0.5 * sin(_age * 12.0)
	if _age >= lifetime:
		queue_free()

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if _is_popped:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pop_bubble()

func _unhandled_input(event: InputEvent) -> void:
	if _is_popped:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if global_position.distance_to(get_global_mouse_position()) <= 24.0:
			pop_bubble()
			get_viewport().set_input_as_handled()

func pop_bubble() -> void:
	if _is_popped:
		return
	_is_popped = true
	bubble_popped.emit(bonus_amount)
	
	# Pop bounce & float up
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_root, "scale", BASE_SCALE * 1.4, 0.2).set_trans(Tween.TRANS_BACK)
	tween.tween_property(visual_root, "position:y", visual_root.position.y - 25.0, 0.25)
	tween.tween_property(visual_root, "modulate:a", 0.0, 0.25)
	tween.finished.connect(queue_free)
