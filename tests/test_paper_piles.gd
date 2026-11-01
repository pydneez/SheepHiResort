extends "res://tests/game_test.gd"
## The paper pile on the mat matches the papers the guest hands over each day.

func _initialize() -> void:
	print("test_paper_piles")
	await load_game(1)
	var expected := {1: "nameplate_id.png", 2: "nameplate_id_and_health.png",
		4: "nameplate_id_and_health.png", 5: "nameplate_all.png", 7: "nameplate_all.png"}
	for d in expected:
		desk.start_day(d)
		continue_popup()
		desk._on_bell()
		await wait_while(desk.State.WALKING_IN)
		var pile: String = desk.pile_btn.texture_normal.resource_path.get_file()
		check(pile == expected[d], "day %d shows %s (got %s)" % [d, expected[d], pile])
	finish()
