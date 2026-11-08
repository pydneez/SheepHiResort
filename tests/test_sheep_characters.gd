extends "res://tests/game_test.gd"
## Checks every drawn sheep in data/sheep_characters, so a missing face, a box
## cut outside the sheet or a missing pixel sprite shows up as a red check on
## the pull request with the sheep's name.

func _initialize() -> void:
	print("test_sheep_characters")
	var chars := SheepCharacters.new()
	check(not chars.all.is_empty(), "there are drawn sheep (%d)" % chars.all.size())
	check(not chars.playable.is_empty(), "some sheep can be used in the game (%d)" % chars.playable.size())
	for id in chars.all:
		_check_character(id, chars.get_character(id))
	for id in chars.all:
		if not chars.playable.has(id):
			print("  note  %s is not used yet (needs a pixel sprite and a normal face)" % id)
	finish()

func _check_character(id: String, c: SheepCharacter) -> void:
	print(id)
	var problems := []
	if c.body == null:
		problems.append("has no body")
	elif not _inside_sheet(c.body):
		problems.append("body box goes outside its sheet")
	if c.normal_faces().is_empty():
		problems.append("has no normal face")
	var ids := {}
	for f in c.faces:
		if f.id == "" or ids.has(f.id):
			problems.append("face id '%s' is empty or used twice" % f.id)
		ids[f.id] = true
		if f.texture != null and not _inside_sheet(f.texture):
			problems.append("%s box goes outside its sheet" % f.id)
		if f.wolf and f.texture == null:
			problems.append("%s is a wolf face without a picture" % f.id)
	if c.face_scale <= 0.0:
		problems.append("face_scale is not positive")
	if c.desk_scale <= 0.0:
		problems.append("desk_scale is not positive")
	if c.pixel != null and c.pixel.resource_path.get_file() != id + "_pixel.png":
		problems.append("pixel sprite is %s, expected %s_pixel.png" % [c.pixel.resource_path.get_file(), id])
	# The ID photo has to show some of the sheep.
	var photo := c.get_photo_rect()
	if not photo.has_area() or not photo.intersects(c.bounds()):
		problems.append("ID photo box is empty or off the sheep")
	check(problems.is_empty(), "%s is complete%s" % [id, "" if problems.is_empty() else ": " + ", ".join(PackedStringArray(problems))])

## A box cut out of a sheet (AtlasTexture) must lie on that sheet.
func _inside_sheet(t: Texture2D) -> bool:
	if t is AtlasTexture:
		var a := t as AtlasTexture
		return a.atlas != null and Rect2(Vector2.ZERO, a.atlas.get_size()).encloses(a.region)
	return true
