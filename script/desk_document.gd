class_name DeskDocument
extends PanelContainer
## A paper on the desk (scene/desk_document.tscn): ID card, health certificate,
## booking voucher or today's rules. Left-click-drag to move it; right-click a
## field to select it for comparison (emits field_clicked).

signal field_clicked(field: Dictionary, label: Label)

const KEY_COLOR := Color(0.35, 0.3, 0.25)
const VALUE_COLOR := Color(0.08, 0.06, 0.05)
const FIELD_FONT_SIZE := 18

const LOOK_SCENE := preload("res://scene/sheep_look.tscn")

var data: Dictionary
var in_pile := false
var drag_bounds := Rect2()
var _dragging := false
var _grab := Vector2.ZERO

@onready var _title: Label = %Title
@onready var _photo: Control = %Photo
@onready var _fields: GridContainer = %Fields

## Fill the paper with one document's data. Call after adding it to the tree.
## portrait_look: the sheep for the photo (ID card only), see SheepLook.
func setup(doc_data: Dictionary, portrait_look: Dictionary = {}) -> void:
	data = doc_data
	# Each document type has its own paper colour; the rest of the look is in the scene.
	var sb := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.bg_color = data.get("color", sb.bg_color)
	add_theme_stylebox_override("panel", sb)
	_title.text = data.title
	_photo.visible = not portrait_look.is_empty()
	if _photo.visible:
		_show_portrait(portrait_look)
	for f in data.fields:
		var k := Label.new()
		k.text = f.label + ":"
		k.add_theme_color_override("font_color", KEY_COLOR)
		k.add_theme_font_size_override("font_size", FIELD_FONT_SIZE)
		k.mouse_filter = Control.MOUSE_FILTER_PASS
		_fields.add_child(k)
		var v := make_field_label(f, data.type)
		_fields.add_child(v)
		v.gui_input.connect(_on_field_input.bind(v))

## The ID photo: the sheep's head area, scaled to fill the photo box. It shows
## the wool colour the papers CLAIM, which may differ from the real guest.
func _show_portrait(look: Dictionary) -> void:
	var head := SheepParts.HEAD_AREA
	var s := minf(_photo.custom_minimum_size.x / head.size.x, _photo.custom_minimum_size.y / head.size.y)
	var sheep: SheepLook = LOOK_SCENE.instantiate()
	_photo.add_child(sheep)
	sheep.pivot_offset = Vector2.ZERO   # scale from the top-left corner for the crop maths
	sheep.scale = Vector2(s, s)
	sheep.position = -head.position * s + (_photo.custom_minimum_size - head.size * s) * 0.5
	sheep.show_look(look)

## Shared by documents and the computer so every comparable value looks and
## behaves the same.
static func make_field_label(f: Dictionary, source: String) -> Label:
	f["source"] = source
	var v := Label.new()
	v.text = f.text
	v.add_theme_color_override("font_color", VALUE_COLOR)
	v.add_theme_font_size_override("font_size", FIELD_FONT_SIZE)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.set_meta("field", f)
	return v

## Right-click selects things for comparison; left-click always drags.
static func is_compare_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT

func _on_field_input(event: InputEvent, label: Label) -> void:
	if not in_pile and is_compare_click(event):
		field_clicked.emit(label.get_meta("field"), label)
		accept_event()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			move_to_front()
			_dragging = true
			_grab = get_global_mouse_position() - global_position
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var p := get_global_mouse_position() - _grab
		if drag_bounds.size != Vector2.ZERO:
			var sz := size * scale
			p.x = clampf(p.x, drag_bounds.position.x, drag_bounds.end.x - sz.x)
			p.y = clampf(p.y, drag_bounds.position.y, drag_bounds.end.y - sz.y)
		global_position = p
		accept_event()
