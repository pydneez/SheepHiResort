extends Control
## Sheep Hi Resort — front desk controller: day flow, decisions, scoring, grades.
## The layout lives in scene/front_desk.tscn: open it in the Godot editor to move,
## resize or restyle anything. This script finds those nodes by their %unique
## names and makes them behave.

const DOC_SCENE := preload("res://scene/desk_document.tscn")
# The guest's paper pile on the mat; the picture matches the papers they hand over.
const ART_PILE_ID := preload("res://assets/lobby/nameplate_id.png")
const ART_PILE_ID_HEALTH := preload("res://assets/lobby/nameplate_id_and_health.png")
const ART_PILE_ALL := preload("res://assets/lobby/nameplate_all.png") # ID + health certificate + booking voucher

const DOC_SPREAD := Vector2(430, 600) # where the first opened paper lands
const RULES_POS := Vector2(960, 560) # where the rules paper opens
const DOC_BOUNDS := Rect2(0, 48, 1440, 1032) # papers can be dragged anywhere below the top bar
const CLOCK_WARNING := 0.85 # last 15% of the day: clock shakes and blinks
const WOLF_LIMIT := 3 # the 3rd wolf let in ends the game with an F

enum State {BRIEFING, IDLE, WALKING_IN, AT_DESK, WALKING_OUT, DAY_OVER, GAME_OVER}

var state := State.BRIEFING
var run_seed := 0
var day := 1
var rules: Dictionary
var today := 0
var queue: Array = []
var database: Array = []
var guest: Dictionary = {} # the current guest's data (the walking sheep is guest_node)
var clock := 0.0
var day_running := false

# Run-wide stats
var money := 150
var reputation := 70
var residents := 0
var wolves_admitted := 0
var guest_book: Array = [] # residents checked in this week: {name, room}
var wolves_inside := 0 # wolves admitted since the last morning report
var week := {} # the week's totals, for the end-of-week summary
# Per-day stats
var day_stats := {}
var scans_used_today: int = 0

# Inspection
var selected: Array = [] # [[field, label], ...]
var found_flaws: Array = []
var docs_opened := false
var docs: Array[DeskDocument] = []
var rules_doc: DeskDocument

# Scene nodes (see scene/front_desk.tscn)
@onready var guest_node: Guest = %Guest
@onready var pile_btn: ArtButton = %PaperPile
@onready var bell_btn: ArtButton = %Bell
@onready var accept_btn: ArtButton = %AcceptButton
@onready var deny_btn: ArtButton = %DenyButton
@onready var scan_btn: Button = %ScanButton
@onready var clock_art: TextureRect = %Clock
@onready var clock_time: Label = %ClockTime
@onready var speech: SpeechBubble = %SpeechBubble
@onready var papers: Control = %Papers
@onready var computer: ComputerWindow = %ComputerWindow
@onready var file_icon_btn: TextureButton = %FileIconButton
@onready var fix_icon_btn: TextureButton = %FixIconButton
@onready var upward_icon_btn: TextureButton = %UpwardIconButton
@onready var toast: Label = %Toast
@onready var day_popup: DayPopup = %DayPopup
@onready var week_summary: WeekSummary = %WeekSummary
@onready var hud_day: Label = %DayLabel
@onready var hud_date: Label = %DateLabel
@onready var hud_money: Label = %MoneyLabel
@onready var hud_rep: Label = %ReputationLabel
@onready var hud_res: Label = %ResidentsLabel
@onready var queue_label: Label = %GuestsLeftLabel

var pile_home: Vector2 # where the pile sits on the mat (set in the editor)
var clock_home: Vector2 # where the clock sits (it shakes around this point)
@onready var upgrade_shop: UpgradeShopPopup = %UpgradeShopPopup

func _ready() -> void:
	randomize()
	if is_instance_valid(upgrade_shop):
		upgrade_shop.setup(self)
		if not upgrade_shop.upgrade_purchased.is_connected(_on_upgrade_purchased):
			upgrade_shop.upgrade_purchased.connect(_on_upgrade_purchased)
	pile_home = pile_btn.position
	clock_home = clock_art.position
	papers.visible = true
	_connect_scene()
	if not GameManager.dev_pending_week_report.is_empty():
		var req := GameManager.dev_pending_week_report.duplicate(true)
		GameManager.dev_pending_week_report.clear()
		_restore_from_game_manager()
		start_day(clampi(GameManager.current_day, 1, DayRules.LAST_DAY))
		trigger_dev_week_report(req.get("ending", ""))
		return
	if GameManager.ENABLE_PHASE_2 and GameManager.run_started:
		_restore_from_game_manager()
		if GameManager.current_day > DayRules.LAST_DAY:
			day = DayRules.LAST_DAY
			rules = DayRules.for_day(day, GameManager.get_word_of_mouth_bonus())
			today = DayRules.today(day)
			day_stats = {"processed": 0, "correct": 0, "mistakes": 0, "residents": 0, "wolves_caught": 0,
				"wolves_in": 0, "earned": 0, "citations": [], "counted": true}
			_refresh_hud()
			_finish_week("")
		else:
			start_day(GameManager.current_day)
	else:
		_new_week()
		start_day(1)

func _connect_scene() -> void:
	bell_btn.pressed.connect(_on_bell)
	pile_btn.pressed.connect(_on_pile_clicked)
	accept_btn.pressed.connect(decide.bind(true))
	deny_btn.pressed.connect(decide.bind(false))
	scan_btn.pressed.connect(_on_scan)
	file_icon_btn.pressed.connect(computer.toggle)
	fix_icon_btn.pressed.connect(_on_open_resort_layout)
	upward_icon_btn.pressed.connect(_on_open_upgrades)
	%RulesPaper.pressed.connect(_toggle_rules)
	guest_node.right_clicked.connect(_on_guest_right_clicked)
	computer.field_clicked.connect(_on_field_clicked)
	hud_date.gui_input.connect(_on_hud_date_input)
	day_popup.continue_pressed.connect(_on_popup_continue)
	week_summary.play_again.connect(_on_play_again)

# =============================================================================
# Day flow

func start_day(d: int) -> void:
	SfxManager.stop_sfx("Menutheme")
	SfxManager.play_sfx("phase1theme", "Music")
	day = d
	GameManager.current_day = d
	GameManager.reset_day_pool()
	rules = DayRules.for_day(day, GameManager.get_word_of_mouth_bonus())
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
	scans_used_today = 0
	_clear_docs()
	_build_rules_doc()
	computer.show_bookings(database, rules)
	_refresh_queue()
	scan_btn.visible = rules.scanner
	scan_btn.text = "SCAN $%d" % _get_current_scan_cost()
	_refresh_decision_buttons()
	bell_btn.disabled = false
	pile_btn.visible = false
	guest_node.visible = false
	speech.visible = false
	computer.visible = false
	if GameManager.returned_from_layout_editor:
		GameManager.returned_from_layout_editor = false
		state = State.IDLE
		day_popup.visible = false
		_refresh_hud()
		_refresh_monitor_icons()
		return
	state = State.BRIEFING
	var missing := _overnight_report()
	_refresh_hud()
	_refresh_monitor_icons()
	day_popup.show_text("[center][b]DAY %d[/b]  —  %s[/center]\n\n%s%s\n\nGuests in line: %d\nBoss's quota: %d valid residents\n\n[i]Ring the bell to open the desk.[/i]" % [
		day, DayRules.format_date(today), missing, rules.news, queue.size(), rules.quota], "Start shift")

## Every wolf let in yesterday makes one resident disappear overnight.
func _overnight_report() -> String:
	if GameManager.ENABLE_PHASE_2:
		wolves_inside = GameManager.wolves_escaped_unharmed
		GameManager.wolves_escaped_unharmed = 0
	if wolves_inside == 0:
		return ""
	var lines := PackedStringArray()
	for i in wolves_inside:
		if not GameManager.stayover_guests.is_empty():
			GameManager.stayover_guests.pop_back()
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
	SfxManager.play_sfx("BellRing", "SFX")
	if state != State.IDLE:
		return
	bell_btn.disabled = true
	day_running = true
	_refresh_monitor_icons()
	speech.say("[DING] Next guest, please!")
	call_next_guest()

func call_next_guest() -> void:
	if state == State.GAME_OVER:
		return
	#SfxManager.play_sfx("Sheep_footstep1", "SFX")
	_clear_docs()
	_reset_inspection()
	if queue.is_empty() or clock >= DayRules.DAY_LENGTH_SECONDS:
		end_day()
		return
	guest = queue.pop_front()
	_refresh_queue()
	guest_node.set_look(guest.appearance)
	speech.visible = false
	state = State.WALKING_IN
	guest_node.walk_in().tween_callback(_on_guest_arrived)
	

func _on_guest_arrived() -> void:
	if state == State.GAME_OVER:
		return
	state = State.AT_DESK
	speech.say(guest.greeting)
	# The guest's papers are created now but stay hidden; what you see is the
	# drawn paper pile sliding down onto the mat. Clicking the pile opens them.
	var defs := SheepGenerator.build_documents(guest, rules)
	var types := defs.map(func(d): return d.type)
	var pile_tex: Texture2D = ART_PILE_ID
	if types.has("voucher"):
		pile_tex = ART_PILE_ALL
	elif types.has("health"):
		pile_tex = ART_PILE_ID_HEALTH
	pile_btn.set_art(pile_tex)
	for def in defs:
		var doc := _spawn_doc(def)
		doc.in_pile = true
		doc.visible = false
	pile_btn.visible = true
	pile_btn.disabled = false
	pile_btn.position = pile_home + Vector2(0, -120)
	pile_btn.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(pile_btn, "position", pile_home, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(pile_btn, "modulate:a", 1.0, 0.25)

## Click on the paper pile: every paper pops out of it onto the desk, readable.
func _on_pile_clicked() -> void:
	SfxManager.play_sfx("Docs_Press", "SFX")
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
		d.position = pile_home + pile_btn.size * 0.5
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
	var is_influ: bool = guest.get("is_influencer", false)
	var flaws: Array = guest.flaws
	# A wolf with perfect papers is still a wolf (it only had a visual giveaway).
	var valid: bool = flaws.is_empty() and not guest.is_wolf
	var reason: String = SheepGenerator.FLAW_TEXT[flaws[0]] if not flaws.is_empty() else "It was a wolf in disguise."
	var proven := false
	for f in found_flaws:
		if f == "scan" or flaws.has(f) or (guest.is_wolf and f == "face"):  # use your real face-flaw key
			proven = true
	day_stats.processed += 1
	var msg := ""
	var good := true
	if accept:
		GameManager.record_admitted_guest(guest)
	if is_influ:
		if accept:
			day_stats.correct += 1
			reputation += 10
			msg = "Influencer admitted!  +10 rep"
			SfxManager.play_sfx("Granted", "SFX")
		else:
			msg = "Influencer turned away."
			SfxManager.play_sfx("MissStep", "SFX")
	elif accept and valid:
		day_stats.correct += 1
		day_stats.residents += 1
		residents += 1
		guest_book.append({"name": guest.papers.name, "room": guest.truth.room})
		if GameManager.ENABLE_PHASE_2:
			reputation += 2
			msg = "Checked in!  +2 rep"
			SfxManager.play_sfx("Granted", "SFX")
		else:
			_earn(10)
			msg = "Checked in. +$10"
			SfxManager.play_sfx("Granted", "SFX")
	elif accept and guest.is_wolf:
		good = false
		day_stats.mistakes += 1
		day_stats.wolves_in += 1
		wolves_admitted += 1
		wolves_inside += 1 # each one makes a resident vanish overnight
		var rep_loss: int = 8 if GameManager.ENABLE_PHASE_2 else 20
		reputation -= rep_loss
		msg = "CITATION: You let a WOLF in! (%s)  -%d rep" % [reason, rep_loss]
		SfxManager.play_sfx("MissStep", "SFX")
	elif accept:
		good = false
		day_stats.mistakes += 1
		var rep_loss: int = 4 if GameManager.ENABLE_PHASE_2 else 5
		reputation -= rep_loss
		guest_book.append({"name": guest.papers.name, "room": guest.truth.room})
		msg = "CITATION: %s  -%d rep" % [reason, rep_loss]
		SfxManager.play_sfx("MissStep", "SFX")
	elif not valid:
		day_stats.correct += 1
		if guest.is_wolf:
			day_stats.wolves_caught += 1
		if GameManager.ENABLE_PHASE_2:
			var rep_gain: int = 5 if proven else 3
			reputation += rep_gain
			msg = ("Denied — wolf caught! " if guest.is_wolf else "Denied — bad papers. ") + \
				("+%d rep (proof bonus!)" % rep_gain if proven else "+%d rep (prove discrepancy for +5 rep)" % rep_gain)
		else:
			var bonus := 5 if proven else 0
			_earn(5 + bonus)
			msg = ("Denied — wolf caught! " if guest.is_wolf else "Denied — bad papers. ") + \
				("+$%d (proof bonus!)" % (5 + bonus) if proven else "+$5 (prove the discrepancy for a bonus)")
		SfxManager.play_sfx("Granted", "SFX")
	else:
		# Denied on suspicion, but the guest was innocent.
		good = false
		day_stats.mistakes += 1
		var rep_loss: int = 4 if GameManager.ENABLE_PHASE_2 else 5
		reputation -= rep_loss
		msg = "CITATION: Turned away a valid guest.  -%d rep" % rep_loss
		SfxManager.play_sfx("MissStep", "SFX")
	if not good:
		day_stats.citations.append(msg)
	reputation = clampi(reputation, 0, 100)
	_toast(msg, Color(0.5, 1, 0.5) if good else Color(1, 0.45, 0.4))
	_refresh_hud()
	speech.say(_reaction(accept))
	

	# The papers simply disappear from the desk, then the guest leaves.
	for d in docs:
		create_tween().tween_property(d, "modulate:a", 0.0, 0.2)
	state = State.WALKING_OUT
	_refresh_decision_buttons()
	var tw := guest_node.walk_out(accept)
	tw.tween_interval(0.3)
	# Instant game over only in standalone Phase 1 mode
	var ending := ""
	if not GameManager.ENABLE_PHASE_2:
		if wolves_admitted >= WOLF_LIMIT:
			ending = "wolves"
		elif reputation <= 0:
			ending = "fired"
	if ending == "":
		tw.tween_callback(call_next_guest)
	else:
		day_running = false
		tw.tween_callback(_finish_week.bind(ending))

func _reaction(accept: bool) -> String:
	if guest.get("is_influencer", false):
		SfxManager.play_sfx("sheep_bleat2", "SFX")
		return "Yay! Tagging #SheepHiResort right now!" if accept else "Ugh, whatever! Unfollowing this resort!"
		
	if guest.is_wolf:
		SfxManager.play_sfx("sheep_baa", "SFX")
		return "Heh heh... dinner is served." if accept else "Grr! You haven't seen the last of me!"
		
	if accept:
		SfxManager.play_sfx("sheep_bleat1", "SFX")
		return ["Thank you! Baa!", "Finally, a soft bed.", "Lovely service!"][randi() % 3]
		
	SfxManager.play_sfx("sheep_bleat1", "SFX")
	return "But... I did everything right! Baa..." if guest.flaws.is_empty() else "Oh no, my papers... I'll fix them."
	
	

func end_day() -> void:
	day_running = false
	state = State.DAY_OVER
	guest_node.visible = false
	speech.visible = false
	SfxManager.play_sfx("Endshift_day", "SFX")
	_clear_docs()
	var left := queue.size()
	queue.clear()
	_refresh_queue()
	var quota_ok: bool = day_stats.residents >= rules.quota
	if not quota_ok:
		var q_loss: int = 4 if GameManager.ENABLE_PHASE_2 else 10
		reputation = clampi(reputation - q_loss, 0, 100)
	else:
		week.quota_days += 1
	_add_day_to_week()
	_refresh_hud()
	if not GameManager.ENABLE_PHASE_2 and reputation <= 0:
		_finish_week("fired")
		return
	var boss := ""
	if not quota_ok:
		boss = "The boss growls: \"Not enough guests. I need more... residents. -%d rep.\"" % (4 if GameManager.ENABLE_PHASE_2 else 10)
	else:
		boss = "The boss smiles a little too widely: \"Good work. The rooms are filling up nicely.\""
	var cites := "\n".join(PackedStringArray(day_stats.citations)) if not day_stats.citations.is_empty() else "None!"
	cites = cites.replace(" rep", " [img=22x20]res://resource/star_icon.tres[/img]")
	boss = boss.replace(" rep", " [img=22x20]res://resource/star_icon.tres[/img]")
	var text := "[center][b]END OF DAY %d — FRONT DESK[/b][/center]\n\nGuests processed: %d   (%d still in line went home)\nCorrect: %d   Mistakes: %d\nWolves caught: %d   Wolves let in: %d\nNew residents: %d / quota %d\nReputation: %d [img=22x20]res://resource/star_icon.tres[/img]\n\n[b]Citations[/b]\n%s\n\n%s" % [
		day, day_stats.processed, left, day_stats.correct, day_stats.mistakes,
		day_stats.wolves_caught, day_stats.wolves_in, day_stats.residents, rules.quota,
		reputation, cites, boss]
	var next_label := "Week summary" if (not GameManager.ENABLE_PHASE_2 and day >= DayRules.LAST_DAY) else ("Proceed to Resort (Phase 2)" if GameManager.ENABLE_PHASE_2 else "Next day")
	day_popup.show_text(text, next_label)

func _on_popup_continue() -> void:
	match state:
		State.BRIEFING:
			state = State.IDLE
			_refresh_monitor_icons()
		State.DAY_OVER:
			if GameManager.ENABLE_PHASE_2:
				SfxManager.play_sfx("Button_Press", "SFX")
				_sync_to_game_manager()
				GameManager.change_scene("res://scene/phase2_resort.tscn")
			elif day >= DayRules.LAST_DAY:
				_finish_week("")
			else:
				start_day(day + 1)

# =============================================================================
# End of the week: grade + summary screen

## Fresh run: money, reputation and the week's totals back to the start.
func _new_week() -> void:
	money = 45 if GameManager.ENABLE_PHASE_2 else 20
	reputation = 0 if GameManager.ENABLE_PHASE_2 else 70
	residents = 0
	wolves_admitted = 0
	wolves_inside = 0
	guest_book.clear()
	week = {"processed": 0, "correct": 0, "wolves_caught": 0, "residents": 0, "quota_days": 0, "earned": 0}
	run_seed = randi()
	GameManager.current_day = 1
	GameManager.run_started = true
	GameManager.init_default_layout(true)
	GameManager.reset_upgrades()
	_sync_to_game_manager()

func _sync_to_game_manager() -> void:
	GameManager.money = money
	GameManager.reputation = reputation
	GameManager.residents = residents
	GameManager.wolves_admitted_total = wolves_admitted
	GameManager.guest_book = guest_book.duplicate(true)
	GameManager.week = week.duplicate(true)
	GameManager.run_seed = run_seed

func _restore_from_game_manager() -> void:
	money = GameManager.money
	reputation = GameManager.reputation
	residents = GameManager.residents
	wolves_admitted = GameManager.wolves_admitted_total
	guest_book = GameManager.guest_book.duplicate(true)
	week = GameManager.week.duplicate(true)
	run_seed = GameManager.run_seed if GameManager.run_seed != 0 else randi()

func _on_open_resort_layout() -> void:
	SfxManager.play_sfx("PC_Press", "SFX")
	if day_running or state != State.IDLE:
		_toast("Resort Editor is only available before starting the day!", Color(1.0, 0.5, 0.4))
		return
	_sync_to_game_manager()
	GameManager.is_layout_edit_mode = true
	GameManager.change_scene("res://scene/phase2_resort.tscn")

func _on_open_upgrades() -> void:
	if day_running or (state != State.IDLE and state != State.BRIEFING):
		_toast("Upgrade Shop is only available before starting the day!", Color(1.0, 0.5, 0.4))
		return
	_sync_to_game_manager()
	if not is_instance_valid(upgrade_shop):
		var shop_scene := preload("res://scene/upgrade_shop_popup.tscn")
		upgrade_shop = shop_scene.instantiate() as UpgradeShopPopup
		add_child(upgrade_shop)
		upgrade_shop.setup(self)
		if not upgrade_shop.upgrade_purchased.is_connected(_on_upgrade_purchased):
			upgrade_shop.upgrade_purchased.connect(_on_upgrade_purchased)
	if upgrade_shop.visible:
		upgrade_shop.close_shop()
	else:
		upgrade_shop.open_shop()

func _on_upgrade_purchased(upgrade_id: String, _new_level: int) -> void:
	if upgrade_id == "word_of_mouth" and not day_running:
		rules = DayRules.for_day(day, GameManager.get_word_of_mouth_bonus())
		var gen := SheepGenerator.new(run_seed, rules)
		var data := gen.generate_day()
		queue = data.guests
		database = data.database
		_clear_docs()
		_build_rules_doc()
		computer.show_bookings(database, rules)
		_refresh_queue()
		_refresh_hud()

func _refresh_monitor_icons() -> void:
	var can_edit := not day_running and (state == State.IDLE or state == State.BRIEFING)
	if is_instance_valid(fix_icon_btn):
		fix_icon_btn.modulate = Color.WHITE if can_edit else Color(0.45, 0.45, 0.45, 0.65)
		fix_icon_btn.tooltip_text = (
			"Resort Layout Editor (Click before starting the day)"
			if can_edit
			else "Resort Layout Editor (Unavailable after starting the day)"
		)
	if is_instance_valid(upward_icon_btn):
		upward_icon_btn.modulate = Color.WHITE if can_edit else Color(0.45, 0.45, 0.45, 0.65)
		upward_icon_btn.tooltip_text = (
			"Upgrade Shop (Click before starting the day)"
			if can_edit
			else "Upgrade Shop (Unavailable after starting the day)"
		)

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
	guest_node.visible = false
	speech.visible = false
	pile_btn.visible = false
	computer.visible = false
	_clear_docs()
	_refresh_decision_buttons()
	var grade := _grade(ending)
	var accuracy: float = 100.0 * week.correct / maxi(week.processed, 1)
	var title: String = {"": "WEEK COMPLETE", "wolves": "THE WOLVES GOT IN", "fired": "YOU'RE FIRED"}[ending]
	var stats := ("Days worked: %d / %d\nGuests processed: %d\nCorrect decisions: %d%%\n"
		+"Wolves caught: %d\nWolves let in: %d / %d\nResidents checked in: %d\nQuota met: %d / %d days\n"
		+"Money earned: $%d\nFinal reputation: %d") % [
		day, DayRules.LAST_DAY, week.processed, roundi(accuracy), week.wolves_caught,
		wolves_admitted, WOLF_LIMIT, week.residents, week.quota_days, day, week.earned, reputation]
	week_summary.show_result(grade, title, stats, _receptionist_line(grade, ending))
	
	#SfxManager.play_sfx("Endshift_week", "SFX")

## S: no wolves, 95%+ correct, quota every day.  A: <=1 wolf, 85%+.  B: <=2 wolves, 70%+.
## D: survived the week below that.  F: 3 wolves or fired (no C on purpose).
func _grade(ending: String) -> String:
	if ending != "":
		return "F"
	var accuracy: float = 100.0 * week.correct / maxi(week.processed, 1)
	if wolves_admitted == 0 and accuracy >= 95.0 and week.quota_days >= DayRules.LAST_DAY:
		SfxManager.play_sfx("Endshift_week", "SFX")
		return "S"
	if wolves_admitted <= 1 and accuracy >= 85.0:
		SfxManager.play_sfx("Endshift_week", "SFX")
		return "A"
	if wolves_admitted <= 2 and accuracy >= 70.0:
		SfxManager.play_sfx("Endshift_week", "SFX")
		return "B"
	SfxManager.play_sfx("Endshift_week", "SFX")
	return "D"

## What the receptionist (the player character) says on the summary.
func _receptionist_line(grade: String, ending: String) -> String:
	if ending == "wolves":
		SfxManager.play_sfx("death1", "SFX")
		return "Three wolves... on my watch. The boss wants to see me in his office. Right now."
	if ending == "fired":
		SfxManager.play_sfx("ghost", "SFX")
		return "They took my name tag. The hotel's reputation is ruined... and so am I."
	return {
		"S": "Not a single wolf got past me! The residents are safe... I could cry!",
		"A": "Almost perfect! One more week like this and I'm employee of the month.",
		"B": "Not bad, not great. I'd better read those papers more carefully.",
		"D": "I survived the week... barely. Let's not talk about the missing residents.",
	}[grade]

func _on_play_again() -> void:
	_new_week()
	start_day(1)
	SfxManager.stop_all_sfx()
	SfxManager.play_sfx("phase1theme", "Music")
	SfxManager.play_sfx("Button_Press", "SFX")

func _process(delta: float) -> void:
	if day_running:
		clock = minf(clock + delta, DayRules.DAY_LENGTH_SECONDS)
		_refresh_clock()
		if clock >= DayRules.DAY_LENGTH_SECONDS:
			_time_up()
	_shake_clock()

# =============================================================================
# Comparing: right-click field A, then right-click field B; the game checks
# they agree. Left-click always drags, so there is no mode to toggle.
# Denying on suspicion is allowed; proving a discrepancy first earns a bonus.

func _time_up() -> void:
	day_running = false # stops this from firing every frame
	_reset_inspection()
	
	if is_instance_valid(rules_doc):
		rules_doc.visible = false
	_finish_week("fired")
	SfxManager.play_sfx("alarmclock")
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_reset_inspection()

func trigger_dev_week_report(ending: String = "") -> void:
	day_popup.hide()
	_finish_week(ending)

func _on_dev_skip_phase1() -> void:
	if GameManager.admitted_guests.is_empty():
		if not queue.is_empty():
			for g in queue:
				GameManager.record_admitted_guest(g)
		else:
			var gen := SheepGenerator.new(randi(), DayRules.for_day(day))
			var data := gen.generate_day()
			for g in data.guests:
				GameManager.record_admitted_guest(g)
	_sync_to_game_manager()
	GameManager.change_scene("res://scene/phase2_resort.tscn")

const HIGHLIGHT_COLOR := Color(1.0, 0.55, 0.0) # strong orange, readable on paper

func _set_highlight(ctrl: Control, on: bool) -> void:
	if ctrl is Label:
		if on:
			if not ctrl.has_meta("orig_font_color"):
				ctrl.set_meta("orig_font_color", ctrl.get_theme_color("font_color"))
			ctrl.add_theme_color_override("font_color", HIGHLIGHT_COLOR)
		elif ctrl.has_meta("orig_font_color"):
			ctrl.add_theme_color_override("font_color", ctrl.get_meta("orig_font_color"))
			ctrl.remove_meta("orig_font_color")
	else:
		# photo and other non-text controls keep the tint
		ctrl.modulate = Color(1.0, 0.75, 0.1) if on else Color.WHITE

func _reset_inspection() -> void:
	for s in selected:
		if is_instance_valid(s[1]):
			_set_highlight(s[1], false)
	selected.clear()

func _on_field_clicked(field: Dictionary, label: Control) -> void:
	if state != State.AT_DESK:
		return
	if not selected.is_empty() and selected[0][1] == label:
		_reset_inspection()   # clicking the same field again deselects it
		return
	_set_highlight(label, true)
	selected.append([field, label])
	if selected.size() == 1:
		return # wait for the second item
	var a: Dictionary = selected[0][0]
	var b: Dictionary = selected[1][0]
	var res := SheepGenerator.compare(a, b, today)
	if not res.comparable:
		_toast("Those two can't be compared.", Color(0.9, 0.9, 0.9))
	elif res.flaw == "":
		_toast("%s and %s match." % [a.label, b.label], Color(0.7, 0.9, 1))
	else:
		var flaw_msg: String = SheepGenerator.FLAW_TEXT.get(res.flaw, "Mismatch: %s" % res.flaw)
		_toast("DISCREPANCY: " + flaw_msg, Color(1, 0.6, 0.2))
		_add_proof(res.flaw)
		speech.say("Wolf? Me? N-no... must be a typo." if guest.is_wolf else "Oh! That... must be a mistake.")
	var labels := [selected[0][1], selected[1][1]]
	selected.clear()
	get_tree().create_timer(0.6).timeout.connect(func():
		for l in labels:
			if is_instance_valid(l):
				_set_highlight(l, false))

func _add_proof(flaw: String) -> void:
	if not found_flaws.has(flaw):
		found_flaws.append(flaw)

func _on_guest_right_clicked() -> void:
	if state == State.AT_DESK:
		var f := SheepGenerator.face_field("Guest's face", guest.appearance.look)
		f["source"] = "sheep"
		_on_field_clicked(f, guest_node.look)

func _on_hud_date_input(event: InputEvent) -> void:
	if DeskDocument.is_compare_click(event):
		_on_field_clicked({"label": "Today", "kind": "today", "value": today,
			"text": DayRules.format_date(today), "source": "clock"}, hud_date)

func _get_current_scan_cost() -> int:
	return int(rules.get("scanner_cost", 100)) + scans_used_today * int(rules.get("scanner_cost_step", 75))

func _on_scan() -> void:
	SfxManager.play_sfx("Scanner_Press", "SFX")
	if state != State.AT_DESK:
		return
	var cost: int = _get_current_scan_cost()
	if money < cost:
		_toast("Not enough money!", Color(1, 0.5, 0.5))
		SfxManager.play_sfx("MissStep", "SFX")
		return
	money -= cost
	GameManager.money = money
	scans_used_today += 1
	scan_btn.text = "SCAN $%d" % _get_current_scan_cost()
	_refresh_hud()
	if guest.get("is_influencer", false):
		_toast("SCANNER: Human Influencer! (Not a sheep, not a wolf)", Color(0.5, 0.9, 1.0))
	elif guest.is_wolf:
		_add_proof("scan")
		_toast("SCANNER: WOLF DNA DETECTED!", Color(1, 0.3, 0.3))
	else:
		_toast("SCANNER: Genuine sheep. (Papers may still be wrong!)", Color(0.6, 1, 0.6))

# =============================================================================
# Papers on the desk

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
	if rules.check_face: checks.append("ID photo matches the guest's face")
	fields.append(SheepGenerator._f("Check", "info", "", "\n".join(PackedStringArray(checks))))
	fields.append(SheepGenerator._f("Reminder", "info", "", "Right Click 2 Information to compare"))
	rules_doc = _spawn_doc({"type": "rules", "title": "RULEBOOK — DAY %d" % day,
		"color": Color(1.0, 0.9, 0.85), "fields": fields}, false)
	rules_doc.position = RULES_POS
	rules_doc.visible = false # opened by clicking the paper drawn on the desk

## The paper drawn on the desk is today's rules: click to open / close it.
func _toggle_rules() -> void:
	rules_doc.visible = not rules_doc.visible
	SfxManager.play_sfx("Rulebook_Press", "SFX")
	if rules_doc.visible:
		SfxManager.play_sfx("Rulebook_Press", "SFX")
		rules_doc.move_to_front()

func _spawn_doc(def: Dictionary, track := true) -> DeskDocument:
	var doc: DeskDocument = DOC_SCENE.instantiate()
	papers.add_child(doc)
	doc.setup(def)
	doc.drag_bounds = DOC_BOUNDS
	doc.field_clicked.connect(_on_field_clicked)
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

# =============================================================================
# Top bar, clock, buttons

func _refresh_queue() -> void:
	queue_label.text = "Guests left %d" % queue.size()

func _refresh_hud() -> void:
	hud_day.text = "DAY %d/%d" % [day, DayRules.LAST_DAY]
	hud_date.text = "[%s]" % DayRules.format_date(today)
	hud_money.text = "%d" % money
	hud_rep.text = "%d" % reputation
	hud_rep.add_theme_color_override("font_color", Color(1, 0.4, 0.4) if reputation < 40 else Color(1, 0.95, 0.85))
	hud_res.text = "Residents today %d/%d" % [day_stats.get("residents", 0), rules.quota]
	_refresh_clock()

func _refresh_clock() -> void:
	var minutes := int(8 * 60 + clock / DayRules.DAY_LENGTH_SECONDS * 600)
	clock_time.text = "%02d:%02d" % [int(minutes / 60.0), minutes % 60]
	if clock >= DayRules.DAY_LENGTH_SECONDS:
		clock_time.text = "CLOSED"
	# Near closing time the digits blink red.
	var warning := day_running and clock >= DayRules.DAY_LENGTH_SECONDS * CLOCK_WARNING
	var blink_red := warning and fmod(clock, 1.0) < 0.5
	clock_time.add_theme_color_override("font_color", Color(1, 0.25, 0.2) if blink_red else Color(1.0, 0.8, 0.25))

## Near closing time the clock shakes in short bursts (every 2 s, for 0.4 s).
## The time label is a child of the clock, so it shakes along.
func _shake_clock() -> void:
	var warning := day_running and clock >= DayRules.DAY_LENGTH_SECONDS * CLOCK_WARNING
	var offset := Vector2.ZERO
	if warning and fmod(clock, 2.0) < 0.4:
		offset = Vector2(randf_range(-4, 4), randf_range(-2, 2))
	clock_art.position = clock_home + offset

## Both decisions unlock once the papers are opened. Locked buttons are dimmed.
func _refresh_decision_buttons() -> void:
	var can_decide := state == State.AT_DESK and docs_opened
	accept_btn.set_locked(not can_decide)
	deny_btn.set_locked(not can_decide)

func _wiggle_bell() -> void:
	var t := create_tween()
	for deg in [-12.0, 10.0, -6.0, 3.0, 0.0]:
		t.tween_property(bell_btn, "rotation_degrees", deg, 0.07)

func _toast(text: String, color: Color) -> void:
	var hbox: HBoxContainer = toast.get_node_or_null("ToastHBox")
	if not is_instance_valid(hbox):
		hbox = HBoxContainer.new()
		hbox.name = "ToastHBox"
		hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 4)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast.add_child(hbox)
	for c in hbox.get_children():
		hbox.remove_child(c)
		c.queue_free()

	if text.contains(" rep"):
		toast.text = ""
		var parts: PackedStringArray = text.split(" rep")
		var star_tex: Texture2D = preload("res://resource/star_icon.tres")
		for i in range(parts.size()):
			if parts[i] != "":
				var seg := Label.new()
				seg.text = parts[i]
				seg.add_theme_color_override("font_color", color)
				seg.add_theme_color_override("font_outline_color", Color.BLACK)
				seg.add_theme_constant_override("outline_size", 8)
				seg.add_theme_font_size_override("font_size", 26)
				seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hbox.add_child(seg)
			if i < parts.size() - 1:
				var icon := TextureRect.new()
				icon.texture = star_tex
				icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				icon.custom_minimum_size = Vector2(26, 24)
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hbox.add_child(icon)
	else:
		toast.text = text
		toast.add_theme_color_override("font_color", color)

	toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(toast, "modulate:a", 0.0, 0.6)

func _earn(amount: int) -> void:
	money += amount
	day_stats.earned += amount
