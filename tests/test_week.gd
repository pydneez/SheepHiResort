extends "res://tests/game_test.gd"
## A perfect player plays a whole week: every guest gets the right decision,
## and every forged paper must be provable by comparing two items.

const SEED := 4242

var _guests_seen := 0
var _unprovable: Array = []

func _initialize() -> void:
	print("test_week")
	await load_game(SEED)
	await play_until_game_over(
		func(g): return g.flaws.is_empty() and not g.is_wolf,
		_check_guest)
	check(_guests_seen > 0, "guests came to the desk (%d)" % _guests_seen)
	check(_unprovable.is_empty(), "every forged paper can be proven %s" % str(_unprovable))
	check(desk.wolves_admitted == 0, "a perfect player lets no wolves in")
	check(desk.week_summary.visible, "the week summary is shown at the end")
	check(desk.day == DayRules.LAST_DAY or desk.reputation <= 0,
		"the game only ends early when fired (day %d, reputation %d)" % [desk.day, desk.reputation])
	finish()

func _check_guest(g: Dictionary) -> void:
	_guests_seen += 1
	for f in g.flaws:
		if not _provable(g, f):
			_unprovable.append("day %d: %s" % [desk.day, f])

## Is there any pair of items the player could right-click that reveals flaw f?
func _provable(g: Dictionary, f: String) -> bool:
	var fields: Array = []
	for doc in SheepGenerator.build_documents(g, desk.rules):
		for x in doc.fields:
			var c: Dictionary = x.duplicate()
			c["source"] = doc.type
			fields.append(c)
	var b: Dictionary = g.truth
	for k in ["name", "id", "region", "species", "wool", "room", "nights"]:
		fields.append({"label": k, "kind": k, "value": b[k], "text": str(b[k]), "source": "db"})
	fields.append({"label": "today", "kind": "today", "value": desk.today, "source": "clock"})
	fields.append({"label": "req", "kind": "required", "value": desk.rules.required_vaccines, "source": "rules"})
	fields.append({"label": "bk", "kind": "booking_list", "value": desk.database.map(func(x): return x.id), "source": "db"})
	fields.append({"label": "sheep", "kind": "wool", "value": g.appearance.wool, "source": "sheep"})
	for a in fields:
		for c in fields:
			var r: Dictionary = SheepGenerator.compare(a, c, desk.today)
			if r.comparable and r.flaw == f:
				return true
	return false
