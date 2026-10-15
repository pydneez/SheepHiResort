class_name DeskDocument
extends PanelContainer
## A paper on the desk. Left-click-drag to move it; right-click a field to
## select it for comparison (emits field_clicked).

signal field_clicked(field: Dictionary, label: Label)
signal pile_clicked(doc: DeskDocument)

var data: Dictionary
var in_pile := false
var drag_bounds := Rect2()
var _dragging := false
var _grab := Vector2.ZERO

func setup(doc_data: Dictionary, portrait: Texture2D = null, portrait_tint := Color.WHITE) -> void:
	data = doc_data
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	var sb := StyleBoxFlat.new()
	sb.bg_color = data.get("color", Color(0.98, 0.96, 0.9))
	sb.border_color = Color(0.15, 0.1, 0.05)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(3, 4)
	add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(vb)
	var title := Label.new()
	title.text = data.title
	title.add_theme_color_override("font_color", Color(0.25, 0.12, 0.05))
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(title)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(row)
	if portrait:
		# The ID photo shows the wool colour the papers CLAIM.
		var pic := TextureRect.new()
		pic.texture = portrait
		pic.modulate = portrait_tint
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(70, 90)
		pic.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(pic)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(grid)
	for f in data.fields:
		var k := Label.new()
		k.text = f.label + ":"
		k.add_theme_color_override("font_color", Color(0.35, 0.3, 0.25))
		k.add_theme_font_size_override("font_size", 13)
		k.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(k)
		var v := make_field_label(f, data.type)
		grid.add_child(v)
		v.gui_input.connect(_on_field_input.bind(v))

## Shared by documents, the computer and the HUD so every inspectable value
## looks and behaves the same.
static func make_field_label(f: Dictionary, source: String) -> Label:
	f["source"] = source
	var v := Label.new()
	v.text = f.text
	v.add_theme_color_override("font_color", Color(0.08, 0.06, 0.05))
	v.add_theme_font_size_override("font_size", 13)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.set_meta("field", f)
	return v

func _on_field_input(event: InputEvent, label: Label) -> void:
	# Right-click compares; left-click falls through to dragging.
	if not in_pile and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		field_clicked.emit(label.get_meta("field"), label)
		accept_event()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if in_pile:
				pile_clicked.emit(self)
				accept_event()
				return
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
