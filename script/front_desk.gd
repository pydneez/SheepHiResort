extends Control
## Sheep Hi Resort — front desk controller.
## The whole game is one screen: lobby viewport on top, desk HUD on the bottom.
## UI is built in code so the layout lives in one place; swap any Button/Label
## for your own art later without touching the game logic.

const LOBBY_BACK := preload("res://assets/lobby_background.png")    # behind the sheep
const LOBBY_FRONT := preload("res://assets/lobby_foreground.png")   # counter + lower desk, in front of the sheep

# Desk items: texture and top-left position on the 1440x1080 canvas, measured
# against assets/lobby_reference.png (the artist's full composition).
const ART_MONITOR := preload("res://assets/monitor.png")
const ART_PLATE := preload("res://assets/plate.png")                 # mat + pen
# Guest's papers lying on the mat; the picture matches which papers they handed over.
const ART_PILE_ID := preload("res://assets/nameplate_id.png")
const ART_PILE_ID_HEALTH := preload("res://assets/nameplate_id_and_health.png")
const ART_PILE_ALL := preload("res://assets/nameplate_all.png")      # ID + health certificate + booking voucher
const ART_BELL := preload("res://assets/bell.png")
const ART_CLOCK := preload("res://assets/clock.png")
const ART_ACCEPT := preload("res://assets/accept_button.png")
const ART_ACCEPT_DOWN := preload("res://assets/accept_button_pushed.png")
const ART_DENY := preload("res://assets/deny_button.png")
const ART_DENY_DOWN := preload("res://assets/deny_button_pushed.png")
const MONITOR_SCALE := 0.8                  # drawn a bit large; shown at 80%
const MONITOR_POS := Vector2(988.8, 300)    # right edge of the image on the screen edge (1440 - 564 * 0.8); stand rests on the counter
const PLATE_POS := Vector2(380, 562)
const PILE_POS := Vector2(537, 676)
const BELL_POS := Vector2(137, 605)
const CLOCK_POS := Vector2(500, 807)
const ACCEPT_POS := Vector2(18, 928)
const DENY_POS := Vector2(270, 927)
const MONITOR_SCREEN_IN_ART := Rect2(73, 102, 436, 310)   # empty white screen inside monitor.png
const CLOCK_DISPLAY := Rect2(589, 888, 213, 59)     # empty black display inside clock.png
const RULES_PAPER := Rect2(940, 975, 400, 105)      # the paper drawn on the desk (bottom right) = today's rules

const SCREEN := Vector2(1440, 1080)
const SHEEP_SIZE := Vector2(540, 540)       # current full-body sprites
const SHEEP_STOP := Vector2(410, 192)       # centred over the mat (x 680), feet behind the counter top (y 655)
const SHEEP_ENTER_X := -560.0
const SHEEP_EXIT_X := 1480.0
const DOC_SPREAD := Vector2(430, 600)       # where the first opened paper lands
const RULES_POS := Vector2(960, 560)        # where the rules paper opens
const CLOCK_WARNING := 0.85                 # last 15% of the day: clock shakes and blinks
const DOC_BOUNDS := Rect2(0, 48, 1440, 1032)

enum State { BRIEFING, IDLE, WALKING_IN, AT_DESK, WALKING_OUT, DAY_OVER, GAME_OVER }

var state := State.BRIEFING
var run_seed := 0
var day := 1
var rules: Dictionary
var today := 0
var queue: Array = []
var database: Array = []
var guest: Dictionary = {}
var clock := 0.0
var day_running := false

# Run-wide stats
var money := 20
var reputation := 70
var residents := 0
var wolves_admitted := 0
var guest_book: Array = []     # residents checked in this week: {name, room}
var wolves_inside := 0         # wolves admitted since the last morning report
var week := {}                 # the week's totals, for the end-of-week summary
# Per-day stats
var day_stats := {}

# Inspection
var selected: Array = []   # [[field, label], ...]
var found_flaws: Array = []
var docs_opened := false

# Nodes
var guest_rect: TextureRect
var doc_layer: Control
var docs: Array[DeskDocument] = []
var rules_doc: DeskDocument
var speech: PanelContainer
var speech_label: Label
var toast: Label
var hud_day: Label
var hud_date: Label
var hud_clock: Label
var hud_money: Label
var hud_rep: Label
var hud_res: Label
var queue_label: Label
var bell_btn: TextureButton
var pile_btn: TextureButton
var clock_rect: TextureRect
var scan_btn: Button
var accept_btn: TextureButton
var deny_btn: TextureButton
var computer: PanelContainer
var db_search: LineEdit
var db_list: ItemList
var db_detail: GridContainer
var db_count: Label
var overlay: ColorRect
var overlay_text: RichTextLabel
var overlay_btn: Button
var summary: Control
var summary_title: Label
var summary_grade: TextureRect
var summary_reaction: TextureRect
var summary_stats: Label
var summary_line: Label

func _ready() -> void:
	randomize()
	run_seed = randi()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # hand-drawn art: smooth scaling
	var t := Theme.new()
	t.default_font_size = 20  # sized for the 1440x1080 canvas
	theme = t
	_build_scene()
	_new_week()
	start_day(1)

# =============================================================================
# Day flow

func start_day(d: int) -> void:
	day = d
	rules = DayRules.for_day(day)
	today = DayRules.today(day)
	var gen := SheepGenerator.new(run_seed, rules)
	var data := gen.generate_day()
	queue = data.guests
	database = data.database
	clock = 0.0
	day_running = false
	guest = {}
	day_stats = {"processed": 0, "correct": 0, "mistakes": 0, "residents": 0, "wolves_caught": 0,
		"wolves_in": 0, "earned": 0, "citations": []}
	_clear_docs()
	_build_rules_doc()
	_refresh_database()
	_refresh_queue()
	_refresh_hud()
	scan_btn.visible = rules.scanner
	scan_btn.text = "SCAN $%d" % rules.scanner_cost
	_refresh_decision_buttons()
	bell_btn.disabled = false
	pile_btn.visible = false
	guest_rect.visible = false
	speech.visible = false
	computer.visible = false
	state = State.BRIEFING
	var missing := _overnight_report()
	_refresh_hud()
	_show_overlay("[center][b]DAY %d[/b]  —  %s[/center]\n\n%s%s\n\nGuests in line: %d\nBoss's quota: %d valid residents\n\n[i]Ring the bell to open the desk.[/i]" % [
		day, DayRules.format_date(today), missing, rules.news, queue.size(), rules.quota], "Start shift")

## Every wolf let in yesterday makes one resident disappear overnight.
func _overnight_report() -> String:
	if wolves_inside == 0:
		return ""
	var lines := PackedStringArray()
	for i in wolves_inside:
		if guest_book.is_empty():
			lines.append("Chewed-up luggage was found in an empty room.")
			continue
		var victim: Dictionary = guest_book.pop_at(randi() % guest_book.size())
		residents = maxi(residents - 1, 0)
		lines.append("MISSING: %s (room %d). Only a tuft of wool remains." % [victim.name, victim.room])
	wolves_inside = 0
	return "[color=#b03030][b]OVERNIGHT REPORT[/b]\n%s[/color]\n\n" % "\n".join(lines)

func _on_bell() -> void:
	_wiggle_bell()
	if state != State.IDLE:
		return
	bell_btn.disabled = true
	day_running = true
	_say("[DING] Next guest, please!")
	call_next_guest()

func call_next_guest() -> void:
	_clear_docs()
	_reset_inspection()
	if queue.is_empty() or clock >= DayRules.DAY_LENGTH_SECONDS:
		end_day()
		return
	guest = queue.pop_front()
	_refresh_queue()
	guest_rect.texture = load(guest.appearance.sprite)
	guest_rect.self_modulate = guest.appearance.tint
	guest_rect.scale = Vector2.ONE * guest.appearance.scale
	guest_rect.flip_h = false
	guest_rect.position = Vector2(SHEEP_ENTER_X, SHEEP_STOP.y)
	guest_rect.visible = true
	speech.visible = false
	state = State.WALKING_IN
	var t := create_tween()
	t.tween_property(guest_rect, "position:x", SHEEP_STOP.x, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_add_bob(1.6)
	t.tween_callback(_on_guest_arrived)

func _on_guest_arrived() -> void:
	state = State.AT_DESK
	_say(guest.greeting)
	# The guest's papers are created now but stay hidden; what you see is the
	# drawn paper pile sliding down onto the mat. Clicking the pile opens them.
	var defs := SheepGenerator.build_documents(guest, rules)
	var types := defs.map(func(d): return d.type)
	var pile_tex: Texture2D = ART_PILE_ID
	if types.has("voucher"):
		pile_tex = ART_PILE_ALL
	elif types.has("health"):
		pile_tex = ART_PILE_ID_HEALTH
	_set_button_art(pile_btn, pile_tex)
	for def in defs:
		var portrait: Texture2D = null
		var tint := Color.WHITE
		if def.type == "id":
			portrait = guest_rect.texture
			tint = SheepGenerator.WOOLS[guest.papers.wool]
		var doc := _spawn_doc(def, portrait, tint)
		doc.in_pile = true
		doc.visible = false
	pile_btn.visible = true
	pile_btn.disabled = false
	pile_btn.position = PILE_POS + Vector2(0, -120)
	pile_btn.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(pile_btn, "position", PILE_POS, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(pile_btn, "modulate:a", 1.0, 0.25)

## Click on the paper pile: every paper pops out of it onto the desk, readable.
func _on_pile_clicked(_doc: DeskDocument = null) -> void:
	if state != State.AT_DESK:
		return
	pile_btn.visible = false
	var i := 0
	for d in docs:
		if not d.in_pile:
			continue
		d.in_pile = false
		d.visible = true
		d.move_to_front()
		d.position = PILE_POS + pile_btn.size * 0.5
		d.scale = Vector2.ONE * 0.2
		var t := create_tween()
		t.tween_property(d, "position", DOC_SPREAD + Vector2(i * 150, i * 50), 0.25).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(d, "scale", Vector2.ONE, 0.25)
		i += 1
	docs_opened = true
	_refresh_decision_buttons()

func decide(accept: bool) -> void:
	if state != State.AT_DESK or not docs_opened:
		return
	accept_btn.disabled = true
	deny_btn.disabled = true
	_reset_inspection()
	var flaws: Array = guest.flaws
	# A wolf with perfect papers is still a wolf (it only had a visual giveaway).
	var valid: bool = flaws.is_empty() and not guest.is_wolf
	var reason: String = SheepGenerator.FLAW_TEXT[flaws[0]] if not flaws.is_empty() else "It was a wolf in disguise."
	var proven := false
	for f in found_flaws:
		if f == "scan" or flaws.has(f):
			proven = true
	day_stats.processed += 1
	var msg := ""
	var good := true
	if accept and valid:
		day_stats.correct += 1
		day_stats.residents += 1
		residents += 1
		guest_book.append({"name": guest.papers.name, "room": guest.truth.room})
		_earn(10)
		msg = "Checked in. +$10"
	elif accept and guest.is_wolf:
		good = false
		day_stats.mistakes += 1
		day_stats.wolves_in += 1
		wolves_admitted += 1
		wolves_inside += 1  # each one makes a resident vanish overnight
		reputation -= 20
		msg = "CITATION: You let a WOLF in! (%s)  -20 rep" % reason
	elif accept:
		good = false
		day_stats.mistakes += 1
		reputation -= 5
		guest_book.append({"name": guest.papers.name, "room": guest.truth.room})
		msg = "CITATION: %s  -5 rep" % reason
	elif not valid:
		day_stats.correct += 1
		if guest.is_wolf:
			day_stats.wolves_caught += 1
		var bonus := 5 if proven else 0
		_earn(5 + bonus)
		msg = ("Denied — wolf caught! " if guest.is_wolf else "Denied — bad papers. ") + \
			("+$%d (proof bonus!)" % (5 + bonus) if proven else "+$5 (prove the discrepancy for a bonus)")
	else:
		# Denied on suspicion, but the guest was innocent.
		good = false
		day_stats.mistakes += 1
		reputation -= 5
		msg = "CITATION: Turned away a valid guest.  -5 rep"
	if not good:
		day_stats.citations.append(msg)
	reputation = clampi(reputation, 0, 100)
	_toast(msg, Color(0.5, 1, 0.5) if good else Color(1, 0.45, 0.4))
	_refresh_hud()
	_say(_reaction(accept))

	# The papers simply disappear from the desk, then the guest leaves.
	for d in docs:
		create_tween().tween_property(d, "modulate:a", 0.0, 0.2)
	state = State.WALKING_OUT
	_refresh_decision_buttons()
	guest_rect.flip_h = not accept
	var exit_x := SHEEP_EXIT_X if accept else SHEEP_ENTER_X
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(guest_rect, "position:x", exit_x, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): guest_rect.visible = false)
	tw.tween_interval(0.3)
	# Instant game over: the 3rd wolf of the week, or reputation gone (fired).
	var ending := ""
	if wolves_admitted >= WOLF_LIMIT:
		ending = "wolves"
	elif reputation <= 0:
		ending = "fired"
	if ending == "":
		tw.tween_callback(call_next_guest)
	else:
		day_running = false
		tw.tween_callback(_finish_week.bind(ending))
	get_tree().create_timer(0.6).timeout.connect(_add_bob.bind(1.3))

func _reaction(accept: bool) -> String:
	if guest.is_wolf:
		return "Heh heh... dinner is served." if accept else "Grr! You haven't seen the last of me!"
	if accept:
		return ["Thank you! Baa!", "Finally, a soft bed.", "Lovely service!"][randi() % 3]
	return "But... I did everything right! Baa..." if guest.flaws.is_empty() else "Oh no, my papers... I'll fix them."
func end_day() -> void:
	day_running = false
	state = State.DAY_OVER
	guest_rect.visible = false
	speech.visible = false
	_clear_docs()
	var left := queue.size()
	queue.clear()
	_refresh_queue()
	var quota_ok: bool = day_stats.residents >= rules.quota
	if not quota_ok:
		reputation = clampi(reputation - 10, 0, 100)
	else:
		week.quota_days += 1
	_add_day_to_week()
	_refresh_hud()
	if reputation <= 0:
		_finish_week("fired")
		return
	var boss := ""
	if not quota_ok:
		boss = "The boss growls: \"Not enough guests. I need more... residents. -10 rep.\""
	else:
		boss = "The boss smiles a little too widely: \"Good work. The rooms are filling up nicely.\""
	var cites := "\n".join(PackedStringArray(day_stats.citations)) if not day_stats.citations.is_empty() else "None!"
	var text := "[center][b]END OF DAY %d[/b][/center]\n\nGuests processed: %d   (%d still in line went home)\nCorrect: %d   Mistakes: %d\nWolves caught: %d   Wolves let in: %d\nNew residents: %d / quota %d\nEarned today: $%d\n\n[b]Citations[/b]\n%s\n\n%s" % [
		day, day_stats.processed, left, day_stats.correct, day_stats.mistakes,
		day_stats.wolves_caught, day_stats.wolves_in, day_stats.residents, rules.quota,
		day_stats.earned, cites, boss]
	_show_overlay(text, "Week summary" if day >= DayRules.LAST_DAY else "Next day")

func _on_overlay_button() -> void:
	overlay.visible = false
	match state:
		State.BRIEFING:
			state = State.IDLE
		State.DAY_OVER:
			if day >= DayRules.LAST_DAY:
				_finish_week("")
			else:
				start_day(day + 1)

# =============================================================================
# End of the week: grade + summary screen

const WOLF_LIMIT := 3   # the 3rd wolf let in ends the game with an F

## Fresh run: money, reputation and the week's totals back to the start.
func _new_week() -> void:
	money = 20
	reputation = 70
	residents = 0
	wolves_admitted = 0
	wolves_inside = 0
	guest_book.clear()
	week = {"processed": 0, "correct": 0, "wolves_caught": 0, "residents": 0, "quota_days": 0, "earned": 0}
	run_seed = randi()

## Folds a (possibly unfinished) day into the week's totals, once per day.
func _add_day_to_week() -> void:
	if day_stats.get("counted", false):
		return
	day_stats.counted = true
	for k in ["processed", "correct", "wolves_caught", "residents", "earned"]:
		week[k] += day_stats.get(k, 0)

## ending: "" = survived all 7 days, "wolves" = 3rd wolf let in, "fired" = reputation 0.
func _finish_week(ending: String) -> void:
	_add_day_to_week()
	day_running = false
	state = State.GAME_OVER
	guest_rect.visible = false
	speech.visible = false
	pile_btn.visible = false
	computer.visible = false
	_clear_docs()
	_refresh_decision_buttons()
	var grade := _grade(ending)
	var accuracy: float = 100.0 * week.correct / maxi(week.processed, 1)
	summary_grade.texture = load("res://assets/grade_%s.png" % grade.to_lower())
	summary_reaction.texture = load("res://assets/reaction_%s.png" % grade.to_lower())
	summary_title.text = {"": "WEEK COMPLETE", "wolves": "THE WOLVES GOT IN", "fired": "YOU'RE FIRED"}[ending]
	summary_stats.text = ("Days worked: %d / %d\nGuests processed: %d\nCorrect decisions: %d%%\n"
		+ "Wolves caught: %d\nWolves let in: %d / %d\nResidents checked in: %d\nQuota met: %d / %d days\n"
		+ "Money earned: $%d\nFinal reputation: %d") % [
		day, DayRules.LAST_DAY, week.processed, roundi(accuracy), week.wolves_caught,
		wolves_admitted, WOLF_LIMIT, week.residents, week.quota_days, day, week.earned, reputation]
	summary_line.text = "\"%s\"" % _receptionist_line(grade, ending)
	summary.visible = true
	summary.move_to_front()

## S: no wolves, 95%+ correct, quota every day.  A: <=1 wolf, 85%+.  B: <=2 wolves, 70%+.
## D: survived the week below that.  F: 3 wolves or fired (no C on purpose).
func _grade(ending: String) -> String:
	if ending != "":
		return "F"
	var accuracy: float = 100.0 * week.correct / maxi(week.processed, 1)
	if wolves_admitted == 0 and accuracy >= 95.0 and week.quota_days >= DayRules.LAST_DAY:
		return "S"
	if wolves_admitted <= 1 and accuracy >= 85.0:
		return "A"
	if wolves_admitted <= 2 and accuracy >= 70.0:
		return "B"
	return "D"

## What the receptionist (the player character) says on the summary.
func _receptionist_line(grade: String, ending: String) -> String:
	if ending == "wolves":
		return "Three wolves... on my watch. The boss wants to see me in his office. Right now."
	if ending == "fired":
		return "They took my name tag. The hotel's reputation is ruined... and so am I."
	return {
		"S": "Not a single wolf got past me! The residents are safe... I could cry!",
		"A": "Almost perfect! One more week like this and I'm employee of the month.",
		"B": "Not bad, not great. I'd better read those papers more carefully.",
		"D": "I survived the week... barely. Let's not talk about the missing residents.",
	}[grade]

func _on_play_again() -> void:
	summary.visible = false
	_new_week()
	start_day(1)

func _process(delta: float) -> void:
	if day_running:
		clock = minf(clock + delta, DayRules.DAY_LENGTH_SECONDS)
		_refresh_clock()
	_shake_clock()

# =============================================================================
# Comparing: right-click field A, then right-click field B; the game checks
# they agree. Left-click always drags, so there is no mode to toggle.
# Denying on suspicion is allowed; proving a discrepancy first earns a bonus.

static func is_compare_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_reset_inspection()

func _reset_inspection() -> void:
	_clear_selection()

func _clear_selection() -> void:
	for s in selected:
		if is_instance_valid(s[1]):
			s[1].modulate = Color.WHITE
	selected.clear()

func _on_field_clicked(field: Dictionary, label: Control) -> void:
	if state != State.AT_DESK:
		return
	if not selected.is_empty() and selected[0][1] == label:
		_reset_inspection()
		return
	label.modulate = Color(1.0, 0.75, 0.1)
	selected.append([field, label])
	if selected.size() == 1:
		return  # wait for the second item
	var a: Dictionary = selected[0][0]
	var b: Dictionary = selected[1][0]
	var res := SheepGenerator.compare(a, b, today)
	if not res.comparable:
		_toast("Those two can't be compared.", Color(0.9, 0.9, 0.9))
	elif res.flaw == "":
		_toast("%s and %s match." % [a.label, b.label], Color(0.7, 0.9, 1))
	else:
		_toast("DISCREPANCY: " + SheepGenerator.FLAW_TEXT[res.flaw], Color(1, 0.6, 0.2))
		_add_proof(res.flaw)
		_say("Wolf? Me? N-no... must be a typo." if guest.is_wolf else "Oh! That... must be a mistake.")
	var labels := [selected[0][1], selected[1][1]]
	selected.clear()
	get_tree().create_timer(0.6).timeout.connect(func():
		for l in labels:
			if is_instance_valid(l):
				l.modulate = Color.WHITE)

func _add_proof(flaw: String) -> void:
	if not found_flaws.has(flaw):
		found_flaws.append(flaw)
	_refresh_decision_buttons()

func _on_guest_input(event: InputEvent) -> void:
	# The guest themself can be compared (their real wool colour).
	if is_compare_click(event) and state == State.AT_DESK:
		var w: String = guest.appearance.wool
		_on_field_clicked({"label": "Guest's wool", "kind": "wool", "value": w, "text": w, "source": "sheep"}, guest_rect)
		guest_rect.accept_event()

func _on_scan() -> void:
	if state != State.AT_DESK:
		return
	if money < rules.scanner_cost:
		_toast("Not enough money for a scan.", Color(1, 0.5, 0.5))
		return
	money -= rules.scanner_cost
	_refresh_hud()
	if guest.is_wolf:
		_add_proof("scan")
		_toast("SCANNER: WOLF DNA DETECTED!", Color(1, 0.3, 0.3))
	else:
		_toast("SCANNER: Genuine sheep. (Papers may still be wrong!)", Color(0.6, 1, 0.6))

# =============================================================================
# Building the screen

func _build_scene() -> void:
	# Back to front: lobby, guest, counter, desk items, then UI on top.
	add_child(_bg(LOBBY_BACK))

	guest_rect = TextureRect.new()
	guest_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guest_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guest_rect.size = SHEEP_SIZE
	guest_rect.pivot_offset = Vector2(SHEEP_SIZE.x * 0.5, SHEEP_SIZE.y)
	guest_rect.visible = false
	guest_rect.gui_input.connect(_on_guest_input)
	add_child(guest_rect)

	add_child(_bg(LOBBY_FRONT))
	_art(ART_PLATE, PLATE_POS)
	_art(ART_MONITOR, MONITOR_POS).scale = Vector2.ONE * MONITOR_SCALE
	clock_rect = _art(ART_CLOCK, CLOCK_POS)

	# Paper pile on the mat: appears when a guest hands over their papers.
	pile_btn = _art_button(ART_PILE_ALL, null, PILE_POS, _on_pile_clicked, "Click to read the guest's papers")
	pile_btn.visible = false

	# The bell opens the desk at the start of the day.
	bell_btn = _art_button(ART_BELL, null, BELL_POS, _on_bell, "Ring the bell to open the desk")
	bell_btn.pivot_offset = Vector2(ART_BELL.get_width() * 0.5, ART_BELL.get_height())

	accept_btn = _art_button(ART_ACCEPT, ART_ACCEPT_DOWN, ACCEPT_POS, decide.bind(true), "ACCEPT the guest")
	deny_btn = _art_button(ART_DENY, ART_DENY_DOWN, DENY_POS, decide.bind(false),
		"DENY the guest. You can deny on suspicion; prove a discrepancy first (right-click two items) for a bonus.")

	# Time is shown on the clock's display.
	hud_clock = Label.new()
	hud_clock.position = CLOCK_DISPLAY.position
	hud_clock.size = CLOCK_DISPLAY.size
	hud_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_clock.add_theme_font_size_override("font_size", 40)
	hud_clock.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
	hud_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_clock)

	# Monitor screen: click to open the reservations window.
	var mon := Button.new()
	mon.flat = true
	mon.position = MONITOR_POS + MONITOR_SCREEN_IN_ART.position * MONITOR_SCALE
	mon.size = MONITOR_SCREEN_IN_ART.size * MONITOR_SCALE
	mon.text = "TODAY'S CHECK-INS\n\nclick to open"
	mon.add_theme_font_size_override("font_size", 22)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		mon.add_theme_color_override(c, Color(0.15, 0.3, 0.4) if c == "font_color" else Color(0.05, 0.15, 0.25))
	mon.focus_mode = Control.FOCUS_NONE
	mon.pressed.connect(func():
		computer.visible = not computer.visible
		computer.move_to_front())
	add_child(mon)

	# The paper drawn on the desk is today's rules: click to open / close it.
	var rules_hotspot := Button.new()
	rules_hotspot.flat = true
	rules_hotspot.position = RULES_PAPER.position
	rules_hotspot.size = RULES_PAPER.size
	rules_hotspot.tooltip_text = "Today's rules"
	rules_hotspot.focus_mode = Control.FOCUS_NONE
	rules_hotspot.pressed.connect(func():
		rules_doc.visible = not rules_doc.visible
		if rules_doc.visible:
			rules_doc.move_to_front())
	add_child(rules_hotspot)

	# No art for the scanner yet: plain button above ACCEPT / DENY.
	scan_btn = _button(self, "SCAN", Color(0.8, 0.6, 1.0), _on_scan)
	scan_btn.position = Vector2(18, 850)
	scan_btn.custom_minimum_size = Vector2(459, 64)

	speech = PanelContainer.new()
	speech.position = Vector2(40, 140)
	speech.custom_minimum_size = Vector2(420, 0)
	speech.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.95), Color(0.1, 0.1, 0.1), 3, 12))
	speech_label = Label.new()
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_label.custom_minimum_size = Vector2(390, 0)
	speech_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	speech.add_child(speech_label)
	speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(speech)

	doc_layer = Control.new()
	doc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doc_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(doc_layer)

	_build_computer()
	_build_hud()

	toast = Label.new()
	toast.position = Vector2(0, 60)
	toast.size = Vector2(1440, 40)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 26)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.add_theme_constant_override("outline_size", 8)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.98, 0.95, 0.87), Color(0.3, 0.2, 0.1), 4, 20))
	panel.position = Vector2(320, 140)
	panel.custom_minimum_size = Vector2(800, 0)
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	overlay_text = RichTextLabel.new()
	overlay_text.bbcode_enabled = true
	overlay_text.fit_content = true
	overlay_text.custom_minimum_size = Vector2(760, 0)
	overlay_text.add_theme_color_override("default_color", Color(0.15, 0.1, 0.05))
	vb.add_child(overlay_text)
	overlay_btn = _button(vb, "OK", Color(0.95, 0.8, 0.3), _on_overlay_button)
	_build_summary()

## End-of-week summary on the artist's template (writable area x 53-1377, y 81-989).
func _build_summary() -> void:
	summary = Control.new()
	summary.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary.visible = false
	add_child(summary)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary.add_child(dim)
	summary.add_child(_bg(preload("res://assets/end_summary.png")))
	var ink := Color(0.24, 0.14, 0.08)

	# The receptionist's reaction, bottom left (below the SUMMARY ribbon).
	summary_reaction = _fit_rect(Rect2(-60, 255, 680, 720))  # picture has empty space on its left
	summary.add_child(summary_reaction)

	summary_title = Label.new()
	summary_title.position = Vector2(640, 110)
	summary_title.add_theme_font_size_override("font_size", 46)
	summary_title.add_theme_color_override("font_color", ink)
	summary.add_child(summary_title)

	summary_stats = Label.new()
	summary_stats.position = Vector2(640, 200)
	summary_stats.size = Vector2(420, 540)
	summary_stats.add_theme_font_size_override("font_size", 26)
	summary_stats.add_theme_constant_override("line_spacing", 10)
	summary_stats.add_theme_color_override("font_color", ink)
	summary.add_child(summary_stats)

	# Grade stamp, top right.
	summary_grade = _fit_rect(Rect2(1000, 180, 370, 440))  # below the title line
	summary.add_child(summary_grade)

	summary_line = Label.new()
	summary_line.position = Vector2(640, 760)
	summary_line.size = Vector2(700, 100)
	summary_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_line.add_theme_font_size_override("font_size", 26)
	summary_line.add_theme_color_override("font_color", Color(0.55, 0.15, 0.3))
	summary.add_child(summary_line)

	var again := _button(summary, "Play again", Color(0.95, 0.8, 0.3), _on_play_again)
	# Centred on the summary paper (x 48-1382).
	again.custom_minimum_size = Vector2(300, 64)
	again.position = Vector2(715 - 150, 900)

## A picture box that keeps the image's shape inside the given area.
func _fit_rect(area: Rect2) -> TextureRect:
	var r := TextureRect.new()
	r.position = area.position
	r.size = area.size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _build_hud() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(Color(0.12, 0.08, 0.05, 0.88), Color(0, 0, 0, 0), 0, 6))
	bar.position = Vector2.ZERO
	bar.custom_minimum_size = Vector2(1440, 48)
	add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 34)
	bar.add_child(hb)
	hud_day = _hud_label(hb)
	hud_date = _hud_label(hb)
	hud_date.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_date.tooltip_text = "Today's date — right-click to compare"
	hud_date.gui_input.connect(_on_hud_date_input)
	hud_money = _hud_label(hb)
	hud_rep = _hud_label(hb)
	hud_res = _hud_label(hb)
	queue_label = _hud_label(hb)

func _on_hud_date_input(event: InputEvent) -> void:
	if is_compare_click(event):
		_on_field_clicked({"label": "Today", "kind": "today", "value": today,
			"text": DayRules.format_date(today), "source": "clock"}, hud_date)

func _build_computer() -> void:
	computer = PanelContainer.new()
	computer.add_theme_stylebox_override("panel", _box(Color(0.08, 0.16, 0.2), Color(0.55, 0.6, 0.62), 4, 8))
	computer.position = Vector2(700, 60)
	computer.custom_minimum_size = Vector2(720, 480)
	computer.visible = false
	add_child(computer)
	var vb := VBoxContainer.new()
	computer.add_child(vb)

	var title := HBoxContainer.new()
	vb.add_child(title)
	var tl := Label.new()
	tl.text = "SHEEP HI RESORT — RESERVATIONS (drag me)"
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_color_override("font_color", Color(0.6, 1, 0.9))
	tl.mouse_filter = Control.MOUSE_FILTER_STOP
	tl.mouse_default_cursor_shape = Control.CURSOR_MOVE
	tl.gui_input.connect(_drag_window.bind(computer))
	title.add_child(tl)
	var close := Button.new()
	close.text = " X "
	close.pressed.connect(func(): computer.visible = false)
	title.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(320, 0)
	body.add_child(left)
	db_search = LineEdit.new()
	db_search.placeholder_text = "Search name or ID…"
	db_search.text_changed.connect(func(_t): _refresh_database())
	left.add_child(db_search)
	db_list = ItemList.new()
	db_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	db_list.custom_minimum_size = Vector2(0, 380)
	db_list.item_selected.connect(_on_db_selected)
	left.add_child(db_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	db_count = Label.new()
	db_count.add_theme_color_override("font_color", Color(0.6, 1, 0.9))
	db_count.mouse_filter = Control.MOUSE_FILTER_STOP
	db_count.tooltip_text = "Inspect this against an ID to check the guest is booked"
	db_count.gui_input.connect(func(e):
		if is_compare_click(e):
			var ids := database.map(func(b): return b.id)
			_on_field_clicked({"label": "Bookings", "kind": "booking_list", "value": ids,
				"text": "bookings", "source": "db"}, db_count))
	right.add_child(db_count)
	db_detail = GridContainer.new()
	db_detail.columns = 2
	db_detail.add_theme_constant_override("h_separation", 12)
	db_detail.add_theme_constant_override("v_separation", 8)
	right.add_child(db_detail)

func _refresh_database() -> void:
	if not db_list:
		return
	db_list.clear()
	var q := db_search.text.strip_edges().to_lower()
	for b in database:
		if q == "" or b.name.to_lower().contains(q) or b.id.to_lower().contains(q):
			var idx := db_list.add_item("%s  %s" % [b.id, b.name])
			db_list.set_item_metadata(idx, b)
	db_count.text = "Today's bookings: %d  [right-click]" % database.size()
	for c in db_detail.get_children():
		c.queue_free()

func _on_db_selected(idx: int) -> void:
	for c in db_detail.get_children():
		c.queue_free()
	var b: Dictionary = db_list.get_item_metadata(idx)
	var fields := [
		SheepGenerator._f("Name", "name", b.name), SheepGenerator._f("ID", "id", b.id),
		SheepGenerator._f("Region", "region", b.region), SheepGenerator._f("Species", "species", b.species)]
	if rules.check_wool:
		fields.append(SheepGenerator._f("Wool", "wool", b.wool))
	if rules.check_voucher:
		fields.append(SheepGenerator._f("Room", "room", b.room))
		fields.append(SheepGenerator._f("Nights", "nights", b.nights))
	for f in fields:
		var k := Label.new()
		k.text = f.label + ":"
		k.add_theme_color_override("font_color", Color(0.5, 0.75, 0.7))
		db_detail.add_child(k)
		var v := DeskDocument.make_field_label(f, "db")
		v.add_theme_color_override("font_color", Color(0.85, 1, 0.95))
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		v.gui_input.connect(func(e):
			if is_compare_click(e):
				_on_field_clicked(f, v))
		db_detail.add_child(v)

func _build_rules_doc() -> void:
	if rules_doc:
		rules_doc.queue_free()
	var fields := [
		SheepGenerator._f("Today", "today", today, DayRules.format_date(today)),
	]
	if rules.check_health:
		fields.append(SheepGenerator._f("Vaccines", "required", rules.required_vaccines,
			", ".join(PackedStringArray(rules.required_vaccines))))
	var checks := ["ID on today's bookings", "Region & species match"]
	if rules.check_health: checks.append("Vaccines present, not expired")
	if rules.check_id_expiry: checks.append("ID not expired")
	if rules.check_voucher: checks.append("Voucher room/nights match")
	if rules.check_wool: checks.append("Wool matches the guest")
	fields.append(SheepGenerator._f("Check", "info", "", "\n".join(PackedStringArray(checks))))
	rules_doc = _spawn_doc({"type": "rules", "title": "RULEBOOK — DAY %d" % day,
		"color": Color(1.0, 0.9, 0.85), "fields": fields}, null, Color.WHITE, false)
	rules_doc.position = RULES_POS
	rules_doc.visible = false  # opened by clicking the paper drawn on the desk

func _spawn_doc(def: Dictionary, portrait: Texture2D, tint: Color, track := true) -> DeskDocument:
	var doc := DeskDocument.new()
	doc.setup(def, portrait, tint)
	doc.drag_bounds = DOC_BOUNDS
	doc.field_clicked.connect(_on_field_clicked)
	doc.pile_clicked.connect(_on_pile_clicked)
	doc_layer.add_child(doc)
	if track:
		docs.append(doc)
	return doc

func _clear_docs() -> void:
	for d in docs:
		if is_instance_valid(d):
			d.queue_free()
	docs.clear()
	docs_opened = false
	found_flaws.clear()

func _refresh_queue() -> void:
	# No lineup sprites for now; just a counter in the top bar.
	if queue_label:
		queue_label.text = "Guests left %d" % queue.size()

func _refresh_hud() -> void:
	hud_day.text = "DAY %d/%d" % [day, DayRules.LAST_DAY]
	hud_date.text = "[%s]" % DayRules.format_date(today)
	hud_money.text = "$%d" % money
	hud_rep.text = "Reputation %d" % reputation
	hud_rep.add_theme_color_override("font_color", Color(1, 0.4, 0.4) if reputation < 40 else Color(1, 0.95, 0.85))
	hud_res.text = "Residents today %d/%d" % [day_stats.get("residents", 0), rules.quota]
	_refresh_clock()

func _refresh_clock() -> void:
	var minutes := int(8 * 60 + clock / DayRules.DAY_LENGTH_SECONDS * 600)
	hud_clock.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	if clock >= DayRules.DAY_LENGTH_SECONDS:
		hud_clock.text = "CLOSED"
	# Near closing time the digits blink red.
	var warning := day_running and clock >= DayRules.DAY_LENGTH_SECONDS * CLOCK_WARNING
	var blink_red := warning and fmod(clock, 1.0) < 0.5
	hud_clock.add_theme_color_override("font_color", Color(1, 0.25, 0.2) if blink_red else Color(1.0, 0.8, 0.25))

## Near closing time the clock shakes in short bursts (every 2 s, for 0.4 s).
func _shake_clock() -> void:
	var warning := day_running and clock >= DayRules.DAY_LENGTH_SECONDS * CLOCK_WARNING
	var offset := Vector2.ZERO
	if warning and fmod(clock, 2.0) < 0.4:
		offset = Vector2(randf_range(-4, 4), randf_range(-2, 2))
	clock_rect.position = CLOCK_POS + offset
	hud_clock.position = CLOCK_DISPLAY.position + offset

# =============================================================================
# Small helpers

func _say(text: String) -> void:
	speech.visible = true
	speech_label.text = text

func _toast(text: String, color: Color) -> void:
	toast.text = text
	toast.add_theme_color_override("font_color", color)
	toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(toast, "modulate:a", 0.0, 0.6)

func _earn(amount: int) -> void:
	money += amount
	day_stats.earned += amount

func _add_bob(duration: float) -> void:
	# Little hop while walking, so a static sprite reads as "walking".
	var t := create_tween().set_loops(int(duration / 0.32))
	t.tween_property(guest_rect, "position:y", SHEEP_STOP.y - 14, 0.16)
	t.tween_property(guest_rect, "position:y", SHEEP_STOP.y, 0.16)

## Both decisions unlock once the papers are opened. Locked buttons are dimmed.
func _refresh_decision_buttons() -> void:
	var can_decide := state == State.AT_DESK and docs_opened
	for b in [accept_btn, deny_btn]:
		b.disabled = not can_decide
		b.modulate = Color.WHITE if can_decide else Color(0.55, 0.55, 0.55)

func _show_overlay(bbcode: String, button_text: String) -> void:
	overlay_text.text = bbcode
	overlay_btn.text = button_text
	overlay.visible = true
	overlay.move_to_front()

var _win_grab := Vector2.ZERO
func _drag_window(event: InputEvent, win: Control) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_win_grab = get_global_mouse_position() - win.global_position
		win.move_to_front()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		win.global_position = (get_global_mouse_position() - _win_grab).clamp(DOC_BOUNDS.position, SCREEN - win.size)

func _bg(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A piece of desk art that doesn't react to the mouse.
func _art(tex: Texture2D, pos: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.position = pos
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

## A piece of desk art you can click. Only its visible pixels are clickable.
func _art_button(tex: Texture2D, pressed_tex: Texture2D, pos: Vector2, cb: Callable, tip: String) -> TextureButton:
	var b := TextureButton.new()
	b.texture_pressed = pressed_tex
	b.position = pos
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	_set_button_art(b, tex)
	b.pressed.connect(cb)
	add_child(b)
	return b

## Swaps a clickable art piece's picture; the click area follows its visible pixels.
func _set_button_art(b: TextureButton, tex: Texture2D) -> void:
	b.texture_normal = tex
	var mask := BitMap.new()
	mask.create_from_image_alpha(tex.get_image())
	b.texture_click_mask = mask

func _wiggle_bell() -> void:
	var t := create_tween()
	for deg in [-12.0, 10.0, -6.0, 3.0, 0.0]:
		t.tween_property(bell_btn, "rotation_degrees", deg, 0.07)

func _button(parent: Control, text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(288, 72)
	b.focus_mode = Control.FOCUS_NONE  # so Space never re-presses ACCEPT/DENY
	b.add_theme_stylebox_override("normal", _box(color, Color(0.15, 0.1, 0.05), 3, 6))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.15), Color(0.15, 0.1, 0.05), 3, 6))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.25), Color(0.15, 0.1, 0.05), 3, 6))
	b.add_theme_stylebox_override("disabled", _box(color.darkened(0.5), Color(0.15, 0.1, 0.05, 0.5), 3, 6))
	b.add_theme_color_override("font_color", Color(0.1, 0.06, 0.03))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.06, 0.03))
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.03))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _hud_label(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.85))
	parent.add_child(l)
	return l

func _box(bg: Color, border: Color, bw: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(margin)
	return s
