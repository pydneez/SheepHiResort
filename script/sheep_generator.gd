class_name SheepGenerator
extends RefCounted
## Procedural guests. Everything comes from one seeded RNG per day, so a given
## (run seed, day) always produces the same queue — handy for debugging.
##
## Rules of the world:
##  * name + ID are ALWAYS truthful and identical on every document and in the
##    database (they are the lookup key).
##  * Everything else (region, species, vaccines, expiry, room, wool...) may be
##    forged. Wolves always carry at least one forged/invalid field.
##  * Some honest sheep are just sloppy and also carry a flaw. Those should be
##    denied too, but turning them away hurts less than letting a wolf in.

const FIRST_NAMES := ["Dolly", "Shaun", "Woolbert", "Fleecy", "Baabara", "Lambert", "Ramona",
	"Cotton", "Nimbus", "Clover", "Barley", "Bramble", "Pippa", "Hector", "Agnes", "Larry",
	"Shirley", "Timmy", "Wooliam", "Lanolin", "Curly", "Biscuit", "Mabel", "Tuft"]
const LAST_NAMES := ["Fleecewood", "Woolsworth", "Baaker", "Lambchop", "Curlyhorn",
	"Hoofington", "Meadows", "Tufton", "Shearling", "Grazely", "Cloudsby", "Mutton"]
const REGIONS := ["Woolington", "Baahamas", "Lambsterdam", "Ewe-tah", "Ramsgate",
	"Fleece Valley", "Mount Muttonmore", "Cloverfield"]
const SPECIES := ["Merino", "Suffolk", "Dorper", "Jacob", "Cheviot", "Texel", "Shetland", "Romney"]
const VACCINES := ["Rabies", "Scrapie", "Anthrax", "Bluetongue"]
const WOOLS := {
	"White": Color(1, 1, 1),
	"Cream": Color(1.0, 0.94, 0.78),
	"Grey": Color(0.78, 0.78, 0.82),
	"Caramel": Color(0.96, 0.82, 0.62),
	"Rose": Color(1.0, 0.84, 0.88),
	"Mint": Color(0.84, 1.0, 0.9),
}
const SHEEP_SPRITES := [
	"res://assets/sheep_character/detective_sheep.png",
	"res://assets/sheep_character/drift_sheep.png",
	"res://assets/sheep_character/robin_sheep.png",
	"res://assets/sheep_character/wiz_sheep.png",
]
const WOLF_SPRITE := "res://assets/sheep_character/wolf_sheep.png"
## Visual wolf giveaways. Only "costume" (wolf_sheep.png) can be drawn today;
## add "red_eyes", "claws", "tail" here once the layered part art exists.
const RENDERABLE_TELLS := ["costume"]
const WOLF_TELL_CHANCE := 0.3

const GREETINGS := ["Baa! I have a reservation.", "Good evening, one room please.",
	"Long trip from %s. I'm exhausted.", "Hello! Is the pool open?",
	"My booking should be under %s.", "Lovely lobby. Here are my papers."]
const WOLF_GREETINGS := ["Baa. Baaa. I am a normal sheep.", "Greetings, fellow... grass eater.",
	"Hurry up, I'm STARVING. For grass. Obviously.", "Nice residents you have here. Very... plump.",
	"I'm from %s. Ask anyone. Don't ask anyone."]

var rng := RandomNumberGenerator.new()
var rules: Dictionary
var today: int

func _init(run_seed: int, day_rules: Dictionary) -> void:
	rules = day_rules
	today = DayRules.today(rules.day)
	rng.seed = hash([run_seed, rules.day])

func pick(arr: Array):
	return arr[rng.randi() % arr.size()]

func pick_other(arr: Array, not_this):
	var v = pick(arr)
	while v == not_this:
		v = pick(arr)
	return v

## Returns { "guests": [...queue order...], "database": [...today's bookings...] }
func generate_day() -> Dictionary:
	var used_ids := {}
	var bookings: Array = []
	var guests: Array = []
	var n: int = rules.guests

	# Honest bookings: everyone who *should* show up, plus a few no-shows so
	# the database isn't a 1:1 answer key.
	for i in n + 3:
		bookings.append(_make_identity(used_ids))

	var booking_pool := bookings.duplicate()
	_shuffle(booking_pool)
	for i in n:
		var is_wolf: bool = rng.randf() < rules.wolf_chance
		var sloppy: bool = not is_wolf and rng.randf() < rules.sloppy_chance
		var truth: Dictionary
		var booked := true
		if is_wolf and rng.randf() < 0.35:
			# Wolf with an unbooked identity (walk-in): caught by DB lookup.
			truth = _make_identity(used_ids)
			booked = false
		else:
			truth = booking_pool.pop_back()
		guests.append(_make_guest(truth, booked, is_wolf, sloppy))

	bookings.sort_custom(func(a, b): return a.name < b.name)
	return {"guests": guests, "database": bookings}

func _make_identity(used_ids: Dictionary) -> Dictionary:
	var id := ""
	while id == "" or used_ids.has(id):
		id = "S-%04d" % rng.randi_range(1000, 9999)
	used_ids[id] = true
	return {
		"name": "%s %s" % [pick(FIRST_NAMES), pick(LAST_NAMES)],
		"id": id,
		"region": pick(REGIONS),
		"species": pick(SPECIES),
		"wool": pick(WOOLS.keys()),
		"room": rng.randi_range(101, 420),
		"nights": rng.randi_range(1, 7),
	}

func _make_guest(truth: Dictionary, booked: bool, is_wolf: bool, sloppy: bool) -> Dictionary:
	var papers := truth.duplicate()
	var actual_wool: String = truth.wool
	var vaccines := {}
	for v in rules.required_vaccines:
		vaccines[v] = today + rng.randi_range(5, 200)
	if rng.randf() < 0.3:  # extra, harmless vaccine
		vaccines[pick(VACCINES)] = today + rng.randi_range(5, 200)
	var guest := {
		"truth": truth,
		"papers": papers,
		"booked": booked,
		"is_wolf": is_wolf,
		"id_expiry": today + rng.randi_range(20, 250),
		"vaccines": vaccines,
		"flaws": [],
	}
	if not booked:
		guest.flaws.append("not_booked")

	# Some wolves show a visual giveaway. Half of those have flawless papers, so
	# only the giveaway (or the scanner) betrays them: deny on suspicion.
	var tell := ""
	if is_wolf and rng.randf() < WOLF_TELL_CHANCE:
		tell = pick(RENDERABLE_TELLS)
	var clean_wolf := tell != "" and booked and rng.randf() < 0.5

	# Corrupt papers so other wolves / sloppy sheep have something to catch.
	var want := 0
	if is_wolf and not clean_wolf:
		want = (1 if booked else 0) + (1 if rng.randf() < 0.4 else 0)
	elif sloppy:
		want = 1
	var options := _flaw_options()
	_shuffle(options)
	for f in options:
		if want <= 0:
			break
		_apply_flaw(guest, f)
		want -= 1
	if is_wolf and not clean_wolf and guest.flaws.is_empty():
		_apply_flaw(guest, "region")

	# Appearance. The wool tint is what the guest *actually* looks like; the
	# "wool" flaw makes their ID claim a different colour.
	if guest.flaws.has("wool"):
		actual_wool = pick_other(WOOLS.keys(), papers.wool)
	var sprite: String = pick(SHEEP_SPRITES)
	if tell == "costume":
		sprite = WOLF_SPRITE  # a lazy disguise
	guest["appearance"] = {
		"sprite": sprite,
		"wool": actual_wool,
		"tint": WOOLS[actual_wool],
		"scale": rng.randf_range(0.92, 1.08),
		"tell": tell,
	}
	guest["greeting"] = _line(WOLF_GREETINGS if is_wolf else GREETINGS, papers)
	return guest

## Seeded Fisher-Yates, so a day's queue is reproducible from its seed.
func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _flaw_options() -> Array:
	var o := ["region", "species"]
	if rules.check_health:
		o.append_array(["vaccine_missing", "vaccine_expired"])
	if rules.check_id_expiry:
		o.append("id_expired")
	if rules.check_voucher:
		o.append_array(["room", "nights"])
	if rules.check_wool:
		o.append("wool")
	return o

func _apply_flaw(g: Dictionary, f: String) -> void:
	if g.flaws.has(f):
		return
	var p: Dictionary = g.papers
	match f:
		"region": p.region = pick_other(REGIONS, p.region)
		"species": p.species = pick_other(SPECIES, p.species)
		"room": p.room = p.room + rng.randi_range(1, 9) * (1 if rng.randf() < 0.5 else -1)
		"nights": p.nights = p.nights % 7 + 1
		"wool": pass  # handled when building the appearance
		"id_expired": g.id_expiry = today - rng.randi_range(1, 60)
		"vaccine_missing":
			if g.flaws.has("vaccine_expired"):
				return  # erasing could delete the expired entry's evidence
			g.vaccines.erase(pick(rules.required_vaccines))
		"vaccine_expired":
			var v: String = pick(rules.required_vaccines)
			if g.flaws.has("vaccine_missing") or not g.vaccines.has(v):
				return
			g.vaccines[v] = today - rng.randi_range(1, 40)
	g.flaws.append(f)

func _line(lines: Array, papers: Dictionary) -> String:
	var l: String = pick(lines)
	if l.contains("%s"):
		l = l % (papers.region if rng.randf() < 0.5 or not l.contains("under") else papers.name)
	return l

# ---------------------------------------------------------------------------
# Documents. Each field: {label, kind, value, text}. "kind" is what the
# inspection system compares on; "value" is the raw value.

static func build_documents(g: Dictionary, r: Dictionary) -> Array:
	var p: Dictionary = g.papers
	var docs: Array = []
	var id_fields := [
		_f("Name", "name", p.name),
		_f("ID", "id", p.id),
		_f("Region", "region", p.region),
		_f("Species", "species", p.species),
	]
	if r.check_wool:
		id_fields.append(_f("Wool", "wool", p.wool))
	if r.check_id_expiry:
		id_fields.append(_f("Expires", "expiry", g.id_expiry, DayRules.format_date(g.id_expiry)))
	docs.append({"type": "id", "title": "SHEEP ID CARD", "color": Color(0.86, 0.93, 1.0), "fields": id_fields})

	if r.check_health:
		var h := [_f("Name", "name", p.name), _f("ID", "id", p.id),
			_f("Vaccines", "vaccines", g.vaccines.keys(), ", ".join(PackedStringArray(g.vaccines.keys())))]
		for v in g.vaccines:
			h.append(_f(v + " until", "vaccine_expiry:" + v, g.vaccines[v], DayRules.format_date(g.vaccines[v])))
		docs.append({"type": "health", "title": "HEALTH CERTIFICATE", "color": Color(0.88, 1.0, 0.88), "fields": h})

	if r.check_voucher:
		docs.append({"type": "voucher", "title": "BOOKING VOUCHER", "color": Color(1.0, 0.95, 0.8), "fields": [
			_f("Name", "name", p.name), _f("ID", "id", p.id),
			_f("Room", "room", p.room), _f("Nights", "nights", p.nights)]})
	return docs

static func _f(label: String, kind: String, value, text = null) -> Dictionary:
	return {"label": label, "kind": kind, "value": value, "text": str(value) if text == null else text}

## Inspection: compare two clicked fields. Returns
##   {"comparable": false} if they can't be compared,
##   {"comparable": true, "flaw": ""} if they agree,
##   {"comparable": true, "flaw": "<code>"} for a discrepancy.
static func compare(a: Dictionary, b: Dictionary, today_ord: int) -> Dictionary:
	for pair in [[a, b], [b, a]]:
		var x: Dictionary = pair[0]
		var y: Dictionary = pair[1]
		if x.kind == "expiry" and y.kind == "today":
			return _res(x.value < today_ord, "id_expired")
		if x.kind.begins_with("vaccine_expiry") and y.kind == "today":
			return _res(x.value < today_ord, "vaccine_expired")
		if x.kind == "vaccines" and y.kind == "required":
			var missing := false
			for v in y.value:
				if not x.value.has(v):
					missing = true
			return _res(missing, "vaccine_missing")
		if x.kind == "id" and y.kind == "booking_list":
			return _res(not y.value.has(x.value), "not_booked")
	if a.kind == b.kind and a.kind in ["name", "id", "region", "species", "room", "nights", "wool"]:
		if a.get("source", "") == b.get("source", ""):
			return {"comparable": false}
		return _res(str(a.value) != str(b.value), a.kind)
	return {"comparable": false}

static func _res(bad: bool, flaw: String) -> Dictionary:
	return {"comparable": true, "flaw": flaw if bad else ""}

const FLAW_TEXT := {
	"not_booked": "No reservation under this ID today.",
	"region": "Region of origin doesn't match the booking.",
	"species": "Species doesn't match the booking.",
	"vaccine_missing": "A required vaccine is missing.",
	"vaccine_expired": "A vaccine has expired.",
	"id_expired": "The ID card has expired.",
	"room": "Room number doesn't match the booking.",
	"nights": "Number of nights doesn't match the booking.",
	"wool": "Wool colour doesn't match the guest.",
}
