extends SceneTree
## Base for the headless gameplay tests in this folder. Run one with:
##   godot --headless --fixed-fps 60 --path . -s res://tests/test_week.gd
## A test calls check() as it goes and finish() at the end. The exit code is 1
## if any check failed, so CI (and you) can see the run failed.

var desk   # the front desk scene, set by load_game()
var _failures := 0

## Loads the main scene, then restarts the week with a fixed seed so every run
## gets the same guests.
func load_game(seed_value: int) -> void:
	desk = load("res://scene/front_desk.tscn").instantiate()
	root.add_child(desk)
	await process_frame
	desk._new_week()
	desk.run_seed = seed_value
	desk.start_day(1)

func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok    ", what)
	else:
		_failures += 1
		print("  FAIL  ", what)

func finish() -> void:
	print("%d check(s) failed" % _failures if _failures > 0 else "all checks passed")
	quit(1 if _failures > 0 else 0)

## Dismiss the briefing / end-of-day popup as if its button was clicked.
func continue_popup() -> void:
	desk.day_popup.hide()
	desk._on_popup_continue()

## Waits while the game is in `state`, at most max_frames frames.
func wait_while(state: int, max_frames := 3000) -> void:
	var n := 0
	while desk.state == state and n < max_frames:
		await process_frame
		n += 1

## Plays from the morning briefing until the game is over, letting `choose`
## decide each guest (true = ACCEPT). on_guest(guest) runs before each decision.
func play_until_game_over(choose: Callable, on_guest := Callable()) -> void:
	var guard := 0
	while desk.state != desk.State.GAME_OVER and guard < 100000:
		guard += 1
		match desk.state:
			desk.State.BRIEFING, desk.State.DAY_OVER:
				continue_popup()
			desk.State.IDLE:
				desk._on_bell()
			desk.State.AT_DESK:
				if not desk.docs_opened:
					desk._on_pile_clicked()
				if on_guest.is_valid():
					on_guest.call(desk.guest)
				desk.decide(choose.call(desk.guest))
		await process_frame
