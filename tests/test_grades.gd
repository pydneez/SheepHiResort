extends "res://tests/game_test.gd"
## The grade table: S / A / B / D for a completed week, F for 3 wolves or fired.

func _initialize() -> void:
	print("test_grades")
	await load_game(1)
	# [case, ending, wolves let in, guests processed, correct, quota days, expected grade]
	var cases := [
		["perfect week", "", 0, 35, 34, 7, "S"],
		["perfect but one quota missed", "", 0, 35, 35, 6, "A"],
		["one wolf, 88% correct", "", 1, 35, 31, 5, "A"],
		["two wolves, 74% correct", "", 2, 35, 26, 4, "B"],
		["two wolves, 57% correct", "", 2, 35, 20, 3, "D"],
		["three wolves", "wolves", 3, 18, 12, 2, "F"],
		["fired", "fired", 2, 25, 10, 1, "F"],
	]
	for c in cases:
		desk._new_week()
		desk.wolves_admitted = c[2]
		desk.week.processed = c[3]
		desk.week.correct = c[4]
		desk.week.quota_days = c[5]
		var got: String = desk._grade(c[1])
		check(got == c[6], "%s -> %s (got %s)" % [c[0], c[6], got])
	finish()
