class_name SheepLook
extends Control
## One drawn sheep (scene/sheep_look.tscn): its body with a face on top. Used
## for the guest at the desk and, cropped to the head, for the ID-card photo.
##
## A look is a Dictionary: {"character": "detective_sheep", "face": "face_02"}
## (see SheepCharacter for where the face goes).

## The look currently shown (see show_look).
var look_data := {}
## true: show only the character's photo_rect, filling the box (the ID photo).
var photo := false

var _character: SheepCharacter
var _face: SheepFace

func show_look(look: Dictionary) -> void:
	look_data = look
	clip_contents = photo
	_character = SheepCharacters.shared().get_character(look.get("character", ""))
	_face = null
	if _character == null:
		push_warning("SheepLook: unknown character '%s'" % look.get("character", ""))
	else:
		_face = _character.face(look.get("face", ""))
		if _face == null:
			push_warning("SheepLook: %s has no face '%s'" % [look.character, look.get("face", "")])
	queue_redraw()

## Mirror the sheep (walking away to the left).
func set_flipped(flipped: bool) -> void:
	scale.x = -absf(scale.x) if flipped else absf(scale.x)

func _draw() -> void:
	if _character == null or _character.body == null:
		return
	# Fit the sheep (or its photo area) into this box: centred, and standing on
	# the bottom edge when shown whole.
	var area := _character.get_photo_rect() if photo else _character.bounds()
	var s := minf(size.x / area.size.x, size.y / area.size.y)
	var offset := Vector2((size.x - area.size.x * s) * 0.5, size.y - area.size.y * s)
	if photo:
		offset.y *= 0.5
	draw_set_transform(offset - area.position * s, 0.0, Vector2(s, s))
	draw_texture_rect(_character.body, Rect2(Vector2.ZERO, _character.body.get_size()), false)
	var fr := _character.face_rect(_face)
	if fr.has_area():
		draw_texture_rect(_face.texture, fr, false)
