class_name SheepCharacter
extends Resource
## One drawn sheep (data/sheep_characters/<id>.tres): a fixed body, the faces
## that can go on it, where they go, and its Phase 2 pixel sprite.
##
## All positions are in body pixels: (0, 0) is the top-left of the body picture.
## Line the faces up with scene/sheep_preview.tscn (open it, press F6).

## The body without a face (or, for the rapper, with one: the "faces" are glasses).
@export var body: Texture2D
@export var faces: Array[SheepFace] = []
## Where the centre of a face goes on the body.
@export var face_anchor := Vector2.ZERO
@export var face_scale := 1.0
## How big this whole sheep stands at the front desk: 1 = normal, 1.2 = 20% bigger.
@export var desk_scale := 1.0
## The part of the sheep shown on the ID-card photo. Empty = the face plus a margin.
@export var photo_rect := Rect2()
## The Phase 2 sprite: assets/sheep_character_pixel/<id>_pixel.png.
@export var pixel: Texture2D

## The file name without .tres, e.g. "detective_sheep".
var id: String:
	get: return resource_path.get_file().get_basename()

func face(face_id: String) -> SheepFace:
	for f in faces:
		if f.id == face_id:
			return f
	return null

func normal_faces() -> Array[SheepFace]:
	return _faces(false)

func wolf_faces() -> Array[SheepFace]:
	return _faces(true)

func _faces(wolf: bool) -> Array[SheepFace]:
	var out: Array[SheepFace] = []
	for f in faces:
		if f.wolf == wolf:
			out.append(f)
	return out

## Where a face is drawn, in body pixels. Empty for a face with no picture.
func face_rect(f: SheepFace) -> Rect2:
	if f == null or f.texture == null:
		return Rect2()
	var size := f.texture.get_size() * face_scale
	return Rect2(face_anchor + f.offset - size * 0.5, size)

## The box every face of this sheep fits in, together with the body: the
## sheep is scaled to this, so changing faces never changes its size.
func bounds() -> Rect2:
	var r := Rect2(Vector2.ZERO, body.get_size() if body else Vector2.ONE)
	for f in faces:
		var fr := face_rect(f)
		if fr.has_area():
			r = r.merge(fr)
	return r

func get_photo_rect() -> Rect2:
	if photo_rect.has_area():
		return photo_rect
	var normal := normal_faces()
	var fr := face_rect(normal[0] if not normal.is_empty() else null)
	if not fr.has_area():
		return Rect2(Vector2.ZERO, body.get_size())
	return fr.grow(fr.size.x * 0.15)
