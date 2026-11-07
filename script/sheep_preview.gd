extends Control
## Sheep preview (scene/sheep_preview.tscn): open it in the editor and press F6
## to line the faces up on each drawn sheep, then press Save.
##
##   drag                 move every face of this sheep (face_anchor)
##   Shift + drag         move only the face shown (its offset)
##   mouse wheel          make the faces bigger / smaller (face_scale)
##   Ctrl + drag / wheel  move / resize the ID photo box (photo_rect)
##   Left / Right         previous / next face
##
## The strip at the bottom shows the sheep with every face, and the ID photo.
## Cutting a new face out of the sheet is done in the .tres itself: select the
## face's Texture (an AtlasTexture) in the Inspector and press "Edit Region".

const LOOK_SCENE := preload("res://scene/sheep_look.tscn")
const INK := Color("3a2a20")
const STRIP_H := 220.0
const PHOTO_SIZE := Vector2(96, 120)   # as on the ID card

var _chars := SheepCharacters.shared()
var _ids: Array = []
var _char: SheepCharacter
var _face_i := 0
var _dirty := {}   # id -> true: changed since the last save

var _view: Control
var _strip: HBoxContainer
var _picker: OptionButton
var _info: Label
var _drag := ""   # "", "anchor", "offset", "photo"
var _drag_from := Vector2.ZERO
var _drag_xform := Transform2D()   # the view stays put while dragging

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("e8dcc4")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 10)
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	_picker = OptionButton.new()
	_ids = _chars.all.keys()
	_ids.sort()
	for id in _ids:
		_picker.add_item(id)
	_picker.item_selected.connect(func(i): _pick(_ids[i]))
	bar.add_child(_picker)
	for b in [["< Face", -1], ["Face >", 1]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(_step_face.bind(b[1]))
		bar.add_child(btn)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	bar.add_child(save)
	_info = Label.new()
	_info.add_theme_color_override("font_color", INK)
	bar.add_child(_info)

	_view = Control.new()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.offset_top = 52
	_view.offset_bottom = -STRIP_H
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_view_input)
	add_child(_view)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scroll.offset_top = -STRIP_H
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 10)
	scroll.add_child(_strip)

	if not _ids.is_empty():
		_pick(_ids[0])

func _pick(id: String) -> void:
	_char = _chars.get_character(id)
	_face_i = 0
	_refresh()

func _step_face(d: int) -> void:
	if _char and not _char.faces.is_empty():
		_face_i = posmod(_face_i + d, _char.faces.size())
		_refresh()

func _face() -> SheepFace:
	return _char.faces[_face_i] if _char and _face_i < _char.faces.size() else null

func _save() -> void:
	for id in _dirty:
		var c := _chars.get_character(id)
		var err := ResourceSaver.save(c, c.resource_path)
		print("Saved %s: %s" % [c.resource_path, error_string(err)])
	_dirty.clear()
	_refresh()

func _changed() -> void:
	_dirty[_char.id] = true
	if _drag == "":
		_refresh()
	else:
		_view.queue_redraw()   # the strip is rebuilt when the drag ends

## Redraw the big view and rebuild the strip of every face + the ID photo.
func _refresh() -> void:
	_view.queue_redraw()
	var f := _face()
	_info.text = "%s%s   face %d/%d: %s%s   anchor %s  scale %.2f  offset %s" % [
		_char.id, " *" if _dirty.has(_char.id) else "",
		_face_i + 1, _char.faces.size(), f.id if f else "-", " (WOLF)" if f and f.wolf else "",
		_char.face_anchor.round(), _char.face_scale, f.offset.round() if f else Vector2.ZERO]
	if _char.pixel == null:
		_info.text += "   — no pixel sprite yet, not used in game"
	for c in _strip.get_children():
		c.queue_free()
	var cells: Array = _char.faces.map(func(x): return [{"character": _char.id, "face": x.id}, false, x.id])
	if f:
		cells.append([{"character": _char.id, "face": f.id}, true, "ID photo"])
	for cell in cells:
		var box := VBoxContainer.new()
		var sheep: SheepLook = LOOK_SCENE.instantiate()
		sheep.photo = cell[1]
		sheep.custom_minimum_size = PHOTO_SIZE if cell[1] else Vector2(130, 180)
		box.add_child(sheep)
		sheep.show_look(cell[0])
		var label := Label.new()
		label.text = cell[2]
		label.add_theme_color_override("font_color", INK)
		label.add_theme_font_size_override("font_size", 13)
		box.add_child(label)
		_strip.add_child(box)

## Body pixels -> view pixels.
func _xform() -> Transform2D:
	if _drag != "":
		return _drag_xform
	var area := _char.bounds().merge(_char.get_photo_rect()).grow(40)
	var s := minf(_view.size.x / area.size.x, _view.size.y / area.size.y)
	var offset := (_view.size - area.size * s) * 0.5 - area.position * s
	return Transform2D(0.0, Vector2(s, s), 0.0, offset)

func _draw_view() -> void:
	if _char == null or _char.body == null:
		return
	_view.draw_set_transform_matrix(_xform())
	var line := 2.0 / _xform().get_scale().x
	_view.draw_texture_rect(_char.body, Rect2(Vector2.ZERO, _char.body.get_size()), false)
	var f := _face()
	var fr := _char.face_rect(f)
	if fr.has_area():
		_view.draw_texture_rect(f.texture, fr, false)
		_view.draw_rect(fr, Color(0.2, 0.5, 1.0, 0.8), false, line)
	var a := _char.face_anchor + (f.offset if f else Vector2.ZERO)
	_view.draw_line(a - Vector2(12, 0) * line, a + Vector2(12, 0) * line, Color.RED, line)
	_view.draw_line(a - Vector2(0, 12) * line, a + Vector2(0, 12) * line, Color.RED, line)
	_view.draw_rect(_char.get_photo_rect(), Color(0.1, 0.6, 0.2, 0.9), false, line)

func _on_view_input(event: InputEvent) -> void:
	if _char == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var k := 1.02 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.02
		if event.ctrl_pressed:
			var r := _char.get_photo_rect()
			_char.photo_rect = Rect2(r.get_center() - r.size * k * 0.5, r.size * k)
		else:
			_char.face_scale *= k
		_changed()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _drag != "" and not event.pressed:
			_drag = ""
			_refresh()
		_drag = ""
		if event.pressed:
			_drag_xform = _xform()
			_drag = "photo" if event.ctrl_pressed else ("offset" if event.shift_pressed and _face() else "anchor")
			_drag_from = event.position
			if _drag == "photo":
				_char.photo_rect = _char.get_photo_rect()   # from automatic to set by hand
	elif event is InputEventMouseMotion and _drag != "":
		var d: Vector2 = (event.position - _drag_from) / _drag_xform.get_scale().x
		_drag_from = event.position
		match _drag:
			"anchor": _char.face_anchor += d
			"offset": _face().offset += d
			"photo": _char.photo_rect.position += d
		_changed()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_step_face(-1)
	elif event.is_action_pressed("ui_right"):
		_step_face(1)
