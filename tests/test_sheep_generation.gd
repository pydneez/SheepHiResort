extends "res://tests/game_test.gd"
## Generates many guests and checks the sheep-look rules are never broken.

const SEEDS := 40   # 40 seeds x 7 days x 5 guests = 1400 guests

func _initialize() -> void:
	print("test_sheep_generation")
	var chars := SheepCharacters.shared()
	var bad := {}   # rule -> first example that broke it

	var guests := []
	var face_day_guests := 0
	for s in SEEDS:
		for d in range(1, DayRules.LAST_DAY + 1):
			var day_guests: Array = SheepGenerator.new(s, DayRules.for_day(d)).generate_day().guests
			for g in day_guests:
				g["day"] = d
			guests.append_array(day_guests)
	check(guests.size() >= 1000, "generated %d guests" % guests.size())

	var wolves_with_tell := 0
	var forged_photos := 0
	var used := {}
	for g in guests:
		var look: Dictionary = g.appearance.look
		var photo: Dictionary = g.appearance.photo
		var name: String = g.papers.name
		var c := chars.get_character(look.character)
		used[look.character] = true
		if c == null or not chars.playable.has(look.character):
			bad.get_or_add("every guest is a playable sheep", "%s: %s" % [name, look.character])
			continue
		var face := c.face(look.face)
		if face == null:
			bad.get_or_add("every face exists on its sheep", "%s: %s %s" % [name, look.character, look.face])
			continue
		if face.wolf and not g.is_wolf:
			bad.get_or_add("normal sheep never have red eyes", name)
		if g.is_wolf and g.appearance.tell != "":
			wolves_with_tell += 1
			if not face.wolf:
				bad.get_or_add("a wolf's giveaway is actually shown", name)
		# The ID photo: the same sheep, never red eyes, a face that exists.
		if photo.character != look.character:
			bad.get_or_add("ID photo is the same sheep", name)
		var pf := c.face(photo.face)
		if pf == null or pf.wolf:
			bad.get_or_add("ID photo shows a normal face of that sheep", "%s: %s" % [name, photo.face])
		var rules := DayRules.for_day(g.day)
		if rules.check_face:
			face_day_guests += 1
			if photo.face != look.face:
				forged_photos += 1
			if (photo.face != look.face) != g.flaws.has("face"):
				bad.get_or_add("once photos are checked, a photo that doesn't match is a flaw", name)
		elif g.flaws.has("face"):
			bad.get_or_add("no photo flaws before photos are checked", name)
		if not g.is_wolf and not g.flaws.has("face") and photo.face != look.face:
			bad.get_or_add("honest sheep with good papers match their photo", name)
	for rule in ["every guest is a playable sheep", "every face exists on its sheep",
			"normal sheep never have red eyes", "a wolf's giveaway is actually shown",
			"ID photo is the same sheep", "ID photo shows a normal face of that sheep",
			"once photos are checked, a photo that doesn't match is a flaw",
			"no photo flaws before photos are checked", "honest sheep with good papers match their photo"]:
		check(not bad.has(rule), rule + ("" if not bad.has(rule) else "  (e.g. %s)" % bad[rule]))
	check(wolves_with_tell > 0, "some wolves show red eyes (%d)" % wolves_with_tell)
	check(forged_photos > 0, "some ID photos are forged on photo days (%d of %d)" % [forged_photos, face_day_guests])
	check(used.size() == chars.playable.size(), "every playable sheep shows up (%d of %d)" % [used.size(), chars.playable.size()])

	# Right-clicking a forged photo and the guest reports the face flaw.
	var forged_guest: Dictionary = guests.filter(func(g): return g.flaws.has("face"))[0]
	var by_photo := SheepGenerator.face_field("ID photo", forged_guest.appearance.photo)
	by_photo["source"] = "id"
	var by_guest := SheepGenerator.face_field("Guest's face", forged_guest.appearance.look)
	by_guest["source"] = "sheep"
	check(SheepGenerator.compare(by_photo, by_guest, 0).flaw == "face", "comparing a forged photo with the guest finds it")

	# Same seed + day -> exactly the same sheep.
	var a: Array = SheepGenerator.new(7, DayRules.for_day(3)).generate_day().guests.map(func(g): return g.appearance)
	var b: Array = SheepGenerator.new(7, DayRules.for_day(3)).generate_day().guests.map(func(g): return g.appearance)
	check(str(a) == str(b), "the same seed gives the same sheep")

	# Every guest carries on into Phase 2 as the pixel version of its sheep.
	var wrong_pixel := guests.filter(func(g):
		return chars.pixel_for(g) != chars.get_character(g.appearance.look.character).pixel)
	check(wrong_pixel.is_empty(), "Phase 2 shows each guest as its own sheep's pixel sprite")

	# In the game, the ID card photo shows the papers' face, the guest their real one.
	await load_game(5)
	desk.start_day(6)
	continue_popup()
	desk._on_bell()
	await wait_while(desk.State.WALKING_IN)
	desk._on_pile_clicked()
	var id_doc = desk.docs.filter(func(d): return d.data.type == "id")[0]
	var photo_look: SheepLook = id_doc.get_node("%Photo").get_child(0)
	check(photo_look.look_data == desk.guest.appearance.photo, "the ID card photo shows the papers' face")
	check(desk.guest_node.look.look_data == desk.guest.appearance.look, "the guest at the desk shows their real face")
	# Right-click the photo, then the guest: the comparison finds a forged photo.
	var forged: bool = desk.guest.appearance.photo.face != desk.guest.appearance.look.face
	id_doc.field_clicked.emit(id_doc.data.photo, id_doc.get_node("%Photo"))
	desk._on_guest_right_clicked()
	check(desk.found_flaws.has("face") == forged, "comparing photo and guest finds a forged photo (forged: %s)" % forged)
	finish()
