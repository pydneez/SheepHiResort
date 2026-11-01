extends "res://tests/game_test.gd"
## Instant game overs: the 3rd wolf let in, and reputation reaching 0 (fired).
## Also checks that "Play again" starts a clean week.

func _initialize() -> void:
	print("test_endings")

	# Accept everyone, but keep reputation topped up so only the wolf rule can end it.
	await load_game(1)
	await play_until_game_over(func(_g): return true,
		func(_g): desk.reputation = 100)
	check(desk.wolves_admitted == 3, "the game ends at exactly 3 wolves (got %d)" % desk.wolves_admitted)
	check(desk.week_summary._title.text == "THE WOLVES GOT IN", "title says the wolves got in")
	check(desk.week_summary._grade.texture.resource_path.ends_with("grade_f.png"), "grade is F")

	desk.week_summary.hide()
	desk._on_play_again()
	await process_frame
	check(desk.day == 1 and desk.wolves_admitted == 0 and desk.reputation == 70 and desk.money == 20,
		"Play again resets day, wolves, reputation and money")

	# Deny everyone: innocent guests cost reputation until the player is fired.
	desk._new_week()
	desk.run_seed = 1
	desk.start_day(1)
	await play_until_game_over(func(_g): return false)
	check(desk.reputation == 0, "reputation reached 0 (got %d)" % desk.reputation)
	check(desk.week_summary._title.text == "YOU'RE FIRED", "title says fired")
	check(desk.week_summary._grade.texture.resource_path.ends_with("grade_f.png"), "grade is F")
	finish()
