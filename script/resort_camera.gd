class_name ResortCamera
extends Camera2D
## Top-down resort camera with WASD / Arrow keys panning, Right-Click drag,
## and smooth mouse wheel zooming.

@export var pan_speed: float = 600.0
@export var min_zoom: float = 0.5
@export var max_zoom: float = 1.6
@export var zoom_step: float = 0.1
@export var zoom_smooth: float = 12.0

# Map boundary limits
@export var limit_rect: Rect2 = Rect2(-1000, -700, 2000, 1400)

var _target_zoom: float = 1.0
var _is_dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	_target_zoom = zoom.x

func _process(delta: float) -> void:
	# Keyboard pan (WASD or Arrow keys)
	var move_input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_input.x += 1.0

	if move_input != Vector2.ZERO:
		position += move_input.normalized() * (pan_speed / zoom.x) * delta
		_clamp_position()

	# Smooth zoom
	var new_zoom: float = lerpf(zoom.x, _target_zoom, zoom_smooth * delta)
	zoom = Vector2(new_zoom, new_zoom)

func _unhandled_input(event: InputEvent) -> void:
	# Right-click drag to pan
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_is_dragging = true
				_drag_start_mouse = event.position
				_drag_start_pos = position
			else:
				_is_dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)

	elif event is InputEventMouseMotion and _is_dragging:
		var delta_mouse: Vector2 = event.position - _drag_start_mouse
		position = _drag_start_pos - (delta_mouse / zoom.x)
		_clamp_position()

func _clamp_position() -> void:
	position.x = clampf(position.x, limit_rect.position.x, limit_rect.end.x)
	position.y = clampf(position.y, limit_rect.position.y, limit_rect.end.y)
