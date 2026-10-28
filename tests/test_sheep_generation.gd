extends "res://tests/game_test.gd"
## Generates many guests and checks the sheep-look rules are never broken.

const SEEDS := 40   # 40 seeds x 7 days x 5 guests = 1400 guests

func _initialize() -> void:
	print("test_sheep_generation")
	var cat := SheepParts.shared()
	var colours := SheepColours.shared()
	var bad := {}   # rule -> first example that broke it

	var guests := []
	for s in SEEDS:
		for d in range(1, DayRules.LAST_DAY + 1):
			guests.append_array(SheepGenerator.new(s, DayRules.for_day(d)).generate_day().guests)
	check(guests.size() >= 1000, "generated %d guests" % guests.size())

	var wolves_with_tell := 0
	for g in guests:
		var look: Dictionary = g.appearance.look
		var claimed: Dictionary = g.appearance.claimed_look
		var name: String = g.papers.name
		# Spelled out here (not via SheepColours.allowed) so a broken rule can't pass itself.
		var wool_tag: String = colours.wool(look.wool).tag
		var outfit_tag: String = colours.outfit(look.outfit).tag
		if (outfit_tag == "dark" and wool_tag == "dark") or (outfit_tag == "loud" and wool_tag != "light"):
			bad.get_or_add("outfit suits the wool (no dark on dark, loud only on light)", "%s: %s wool, %s outfit" % [name, look.wool, look.outfit])
		if wool_tag == "dark" and colours.skin(look.skin).tag == "dark":
			bad.get_or_add("no dark face on dark wool", "%s: %s wool, %s skin" % [name, look.wool, look.skin])
		for slot in SheepParts.REQUIRED:
			if not look.parts.has(slot):
				bad.get_or_add("every sheep has %s" % slot, name)
		for slot in look.parts:
			if cat.part(slot, look.parts[slot]).is_empty():
				bad.get_or_add("every part exists in the catalogue", "%s: %s" % [name, look.parts[slot]])
		if look.wool != g.appearance.wool:
			bad.get_or_add("the look's wool is the guest's real wool", name)
		var tell: String = g.appearance.tell
		var wolf_parts := _wolf_parts(cat, look)
		if not g.is_wolf and (not wolf_parts.is_empty() or look.wolf_skin or look.wolf_detail):
			bad.get_or_add("normal sheep never show wolf parts", name)
		if g.is_wolf and tell != "":
			wolves_with_tell += 1
			var shown: bool = (tell == "wolf_skin" and look.wolf_skin) or (tell == "wolf_detail" and look.wolf_detail) \
				or wolf_parts.has(tell)
			if not shown:
				bad.get_or_add("a wolf's giveaway is actually shown", "%s: %s" % [name, tell])
			if tell == "eyes" and look.parts.has("front"):
				bad.get_or_add("glasses never hide red eyes", name)
		# The ID photo: the papers' wool, no wolf parts, otherwise the same sheep.
		if claimed.wool != g.papers.wool:
			bad.get_or_add("ID photo uses the wool the papers claim", name)
		if not _wolf_parts(cat, claimed).is_empty() or claimed.wolf_skin or claimed.wolf_detail:
			bad.get_or_add("ID photo never shows wolf parts", name)
		if claimed.base != look.base or claimed.skin != look.skin or claimed.outfit != look.outfit:
			bad.get_or_add("ID photo is the same sheep (base, skin, outfit)", name)
	for rule in ["outfit suits the wool (no dark on dark, loud only on light)", "no dark face on dark wool", "every part exists in the catalogue",
			"the look's wool is the guest's real wool", "normal sheep never show wolf parts",
			"a wolf's giveaway is actually shown", "glasses never hide red eyes",
			"ID photo uses the wool the papers claim", "ID photo never shows wolf parts",
			"ID photo is the same sheep (base, skin, outfit)"] + SheepParts.REQUIRED.map(func(s): return "every sheep has %s" % s):
		check(not bad.has(rule), rule + ("" if not bad.has(rule) else "  (e.g. %s)" % bad[rule]))
	check(wolves_with_tell > 0, "some wolves show a giveaway (%d)" % wolves_with_tell)

	# Same seed + day -> exactly the same sheep.
	var a: Array = SheepGenerator.new(7, DayRules.for_day(3)).generate_day().guests.map(func(g): return g.appearance)
	var b: Array = SheepGenerator.new(7, DayRules.for_day(3)).generate_day().guests.map(func(g): return g.appearance)
	check(str(a) == str(b), "the same seed gives the same sheep")

	# In the game, the ID card photo shows the claimed look.
	await load_game(5)
	desk.start_day(6)
	continue_popup()
	desk._on_bell()
	await wait_while(desk.State.WALKING_IN)
	desk._on_pile_clicked()
	var id_doc = desk.docs.filter(func(d): return d.data.type == "id")[0]
	var photo: SheepLook = id_doc.get_node("%Photo").get_child(0)
	check(photo.look_data == desk.guest.appearance.claimed_look, "the ID card photo shows the claimed look")
	check(desk.guest_node.look.look_data == desk.guest.appearance.look, "the guest at the desk shows the real look")
	finish()

func _wolf_parts(cat: SheepParts, look: Dictionary) -> Array:
	return look.parts.keys().filter(func(slot): return cat.part(slot, look.parts[slot]).get("wolf", false))
