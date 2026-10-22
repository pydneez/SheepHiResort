extends Control
## Sheep Hi Resort — front desk controller.
## The whole game is one screen: lobby viewport on top, desk HUD on the bottom.
## UI is built in code so the layout lives in one place; swap any Button/Label
## for your own art later without touching the game logic.

const LOBBY_TOP := preload("res://assets/pixel/lobby_up.png")
const LOBBY_BOTTOM := preload("res://assets/pixel/lobby_bottom.png")

# Screen layout on the 640x360 pixel canvas, measured against the lobby art
# (the 640x452 background is centred, so 46px are cropped top and bottom).
const SCREEN := Vector2(640, 360)
const SHEEP_SIZE := Vector2(192, 192)
const SHEEP_STOP := Vector2(224, 30)
const SHEEP_ENTER_X := -200.0
const SHEEP_EXIT_X := 650.0
const PILE_POS := Vector2(150, 196)          # the paper slot on the counter
const MONITOR_RECT := Rect2(467, 189, 123, 109)
const DOC_BOUNDS := Rect2(0, 14, 640, 346)

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
var bell_btn: Button
var scan_btn: Button
var accept_btn: Button
var deny_btn: Button
var inspect_hint: Label
var computer: PanelContainer
var db_search: LineEdit
var db_list: ItemList
var db_detail: GridContainer
var db_count: Label
var overlay: ColorRect
var overlay_text: RichTextLabel
var overlay_btn: Button

func _ready() -> void:
	randomize()
	run_seed = randi()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = PixelTheme.make_theme()
	_build_scene()
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
	accept_btn.disabled = true
	deny_btn.disabled = true
	bell_btn.disabled = false
	guest_rect.visible = false
	speech.visible = false
	computer.visible = false
	state = State.BRIEFING
	var missing := _overnight_report()
	_refresh_hud()
	_show_overlay("[center][b]DAY %d[/b]  -  %s[/center]\n\n%s%s\n\nGuests in line: %d\nBoss's quota: %d valid residents\n\n[i]Ring the bell to open the desk.[/i]" % [
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
	# Documents slide from the sheep onto the counter slot and wait in a pile.
	var defs := SheepGenerator.build_documents(guest, rules)
	var i := 0
	for def in defs:
		var portrait: Texture2D = null
		var tint := Color.WHITE
		if def.type == "id":
			portrait = guest_rect.texture
			tint = SheepGenerator.WOOLS[guest.papers.wool]
		var doc := _spawn_doc(def, portrait, tint)
		doc.in_pile = true
		doc.scale = Vector2.ONE * 0.15
		doc.position = guest_rect.position + SHEEP_SIZE * 0.5
		var t := create_tween()
		t.tween_interval(0.12 * i)
		t.tween_property(doc, "position", PILE_POS + Vector2(i * 6, -i * 3), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(doc, "scale", Vector2.ONE * 0.35, 0.45)
		i += 1

func _on_pile_clicked(_doc: DeskDocument) -> void:
	# Spread every document from the pile onto the desk at full size.
	var i := 0
	for d in docs:
		if not d.in_pile:
			continue
		d.in_pile = false
		d.move_to_front()
		var target := Vector2(86 + i * 80, 220 + i * 14)
		var t := create_tween()
		t.tween_property(d, "position", target, 0.25).set_trans(Tween.TRANS_QUAD)
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
		msg = ("Denied - wolf caught! " if guest.is_wolf else "Denied - bad papers. ") + \
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

	# Hand the papers back, then the guest leaves.
	for d in docs:
		var t := create_tween()
		t.tween_property(d, "position", guest_rect.position + SHEEP_SIZE * 0.5, 0.3)
		t.parallel().tween_property(d, "scale", Vector2.ONE * 0.1, 0.3)
	state = State.WALKING_OUT
	guest_rect.flip_h = not accept
	var exit_x := SHEEP_EXIT_X if accept else SHEEP_ENTER_X
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(guest_rect, "position:x", exit_x, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): guest_rect.visible = false)
	tw.tween_interval(0.3)
	tw.tween_callback(call_next_guest)
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
	_refresh_hud()
	var boss := ""
	if reputation <= 0:
		state = State.GAME_OVER
		boss = "[color=#ff6b6b]The boss bares his fangs: \"Our reputation is in tatters. You're FIRED.\"[/color]"
	elif not quota_ok:
		boss = "The boss growls: \"Not enough guests. I need more... residents. -10 rep.\""
	else:
		boss = "The boss smiles a little too widely: \"Good work. The rooms are filling up nicely.\""
	var cites := "\n".join(PackedStringArray(day_stats.citations)) if not day_stats.citations.is_empty() else "None!"
	var text := "[center][b]END OF DAY %d[/b][/center]\n\nGuests processed: %d   (%d still in line went home)\nCorrect: %d   Mistakes: %d\nWolves caught: %d   Wolves let in: %d\nNew residents: %d / quota %d\nEarned today: $%d\n\n[b]Citations[/b]\n%s\n\n%s" % [
		day, day_stats.processed, left, day_stats.correct, day_stats.mistakes,
		day_stats.wolves_caught, day_stats.wolves_in, day_stats.residents, rules.quota,
		day_stats.earned, cites, boss]
	if state == State.GAME_OVER:
		_show_overlay(text, "Try again")
	elif day >= DayRules.LAST_DAY:
		state = State.GAME_OVER
		_show_overlay(text + "\n\n" + _ending(), "Play again")
	else:
		_show_overlay(text, "Next day")

func _ending() -> String:
	if reputation < 40:
		return "[b]WEEK OVER - FIRED.[/b]\nThe wolf boss replaces you with someone 'more cooperative'."
	if wolves_admitted == 0:
		return "[b]WEEK OVER - PERFECT GUARD.[/b]\nNot a single wolf got in. The boss looks... hungry. And disappointed."
	return "[b]WEEK OVER - YOU KEEP YOUR JOB.[/b]\n%d wolves slipped past you. The residents seem fewer than before..." % wolves_admitted

func _on_overlay_button() -> void:
	overlay.visible = false
	match state:
		State.BRIEFING:
			state = State.IDLE
		State.DAY_OVER:
			start_day(day + 1)
		State.GAME_OVER:
			money = 20
			reputation = 70
			residents = 0
			wolves_admitted = 0
			wolves_inside = 0
			guest_book.clear()
			run_seed = randi()
			start_day(1)

func _process(delta: float) -> void:
	if day_running:
		clock = minf(clock + delta, DayRules.DAY_LENGTH_SECONDS)
		_refresh_clock()

# =============================================================================
# Comparing: right-click field A, then right-click field B; the game checks
# they agree. Left-click always drags, so there is no mode to toggle.
# Denying on suspicion is allowed; proving a discrepancy first earns a bonus.

const HINT_FIRST := "Right-click two items to compare them"
const HINT_SECOND := "Now right-click something to compare it with"

static func is_compare_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_reset_inspection()

func _reset_inspection() -> void:
	_clear_selection()
	inspect_hint.text = HINT_FIRST

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
		inspect_hint.text = HINT_SECOND
		return
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
	inspect_hint.text = HINT_FIRST
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
# Building the screen (640x360 pixel canvas; every widget uses PixelTheme)

func _build_scene() -> void:
	add_child(_bg(LOBBY_TOP))

	guest_rect = TextureRect.new()
	guest_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	guest_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	guest_rect.size = SHEEP_SIZE
	guest_rect.pivot_offset = Vector2(SHEEP_SIZE.x * 0.5, SHEEP_SIZE.y)
	guest_rect.visible = false
	guest_rect.gui_input.connect(_on_guest_input)
	add_child(guest_rect)

	add_child(_bg(LOBBY_BOTTOM))

	# Computer monitor hotspot (click to open the database)
	var mon := Button.new()
	mon.flat = true
	mon.position = MONITOR_RECT.position
	mon.size = MONITOR_RECT.size
	mon.text = "HOTEL DB\n\nclick to open"
	mon.add_theme_color_override("font_color", PixelTheme.SCREEN_DARK)
	mon.add_theme_color_override("font_hover_color", PixelTheme.INK)
	mon.add_theme_color_override("font_pressed_color", PixelTheme.INK)
	mon.focus_mode = Control.FOCUS_NONE
	mon.pressed.connect(func():
		computer.visible = not computer.visible
		computer.move_to_front())
	add_child(mon)

	var col := VBoxContainer.new()
	col.position = Vector2(4, 222)
	col.custom_minimum_size = Vector2(76, 0)
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	bell_btn = _button(col, "RING BELL", PixelTheme.GOLD, _on_bell)
	scan_btn = _button(col, "SCAN", PixelTheme.PURPLE, _on_scan)
	accept_btn = _button(col, "ACCEPT", PixelTheme.GREEN, decide.bind(true))
	deny_btn = _button(col, "DENY", PixelTheme.RED, decide.bind(false))
	deny_btn.tooltip_text = "You can deny on suspicion.\nProve a discrepancy first (right-click two items) for a bonus."

	speech = PanelContainer.new()
	speech.position = Vector2(390, 26)
	speech.add_theme_stylebox_override("panel", PixelTheme.frame(Color.WHITE, 5))
	speech_label = Label.new()
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_label.custom_minimum_size = Vector2(180, 0)
	speech.add_child(speech_label)
	speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(speech)

	doc_layer = Control.new()
	doc_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doc_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(doc_layer)

	_build_computer()
	_build_hud()

	toast = _outlined_label(Vector2(0, 18))
	toast.size = Vector2(640, 10)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast)

	inspect_hint = _outlined_label(Vector2(4, 206))
	inspect_hint.text = HINT_FIRST
	inspect_hint.add_theme_color_override("font_color", PixelTheme.HIGHLIGHT)
	add_child(inspect_hint)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelTheme.frame(PixelTheme.PAPER, 10))
	panel.position = Vector2(120, 24)
	panel.custom_minimum_size = Vector2(400, 0)
	overlay.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	overlay_text = RichTextLabel.new()
	overlay_text.bbcode_enabled = true
	overlay_text.fit_content = true
	overlay_text.custom_minimum_size = Vector2(380, 0)
	vb.add_child(overlay_text)
	overlay_btn = _button(vb, "OK", PixelTheme.GOLD, _on_overlay_button)

func _build_hud() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", PixelTheme.flat(Color(PixelTheme.WOOD_DARK, 0.92), 3))
	bar.position = Vector2.ZERO
	bar.custom_minimum_size = Vector2(640, 14)
	add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)
	hud_day = _hud_label(hb)
	hud_date = _hud_label(hb)
	hud_date.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_date.tooltip_text = "Today's date: right-click to compare"
	hud_date.gui_input.connect(_on_hud_date_input)
	hud_clock = _hud_label(hb)
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
	computer.add_theme_stylebox_override("panel", PixelTheme.frame(PixelTheme.SCREEN, 6))
	computer.position = Vector2(232, 20)
	computer.custom_minimum_size = Vector2(400, 196)
	computer.visible = false
	add_child(computer)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	computer.add_child(vb)

	var title := HBoxContainer.new()
	vb.add_child(title)
	var tl := Label.new()
	tl.text = "RESERVATIONS  (drag me)"
	tl.add_theme_font_override("font", PixelTheme.FONT_BOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.mouse_filter = Control.MOUSE_FILTER_STOP
	tl.mouse_default_cursor_shape = Control.CURSOR_MOVE
	tl.gui_input.connect(_drag_window.bind(computer))
	title.add_child(tl)
	var close := Button.new()
	close.text = "X"
	close.focus_mode = Control.FOCUS_NONE
	PixelTheme.tint_button(close, PixelTheme.RED)
	close.pressed.connect(func(): computer.visible = false)
	title.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(160, 0)
	body.add_child(left)
	db_search = LineEdit.new()
	db_search.placeholder_text = "Search name or ID"
	db_search.text_changed.connect(func(_t): _refresh_database())
	left.add_child(db_search)
	db_list = ItemList.new()
	db_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	db_list.custom_minimum_size = Vector2(0, 140)
	db_list.item_selected.connect(_on_db_selected)
	left.add_child(db_list)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	db_count = Label.new()
	db_count.mouse_filter = Control.MOUSE_FILTER_STOP
	db_count.tooltip_text = "Right-click this, then right-click an ID,\nto check the guest is booked today"
	db_count.gui_input.connect(func(e):
		if is_compare_click(e):
			var ids := database.map(func(b): return b.id)
			_on_field_clicked({"label": "Bookings", "kind": "booking_list", "value": ids,
				"text": "bookings", "source": "db"}, db_count))
	right.add_child(db_count)
	db_detail = GridContainer.new()
	db_detail.columns = 2
	db_detail.add_theme_constant_override("h_separation", 6)
	db_detail.add_theme_constant_override("v_separation", 3)
	right.add_child(db_detail)

func _refresh_database() -> void:
	if not db_list:
		return
	db_list.clear()
	var q := db_search.text.strip_edges().to_lower()
	for b in database:
		if q == "" or b.name.to_lower().contains(q) or b.id.to_lower().contains(q):
			var idx := db_list.add_item("%s %s" % [b.id, b.name])
			db_list.set_item_metadata(idx, b)
	db_count.text = "Today's bookings: %d" % database.size()
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
		k.add_theme_color_override("font_color", PixelTheme.TEXT_MUTED)
		db_detail.add_child(k)
		var v := DeskDocument.make_field_label(f, "db")
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
	rules_doc = _spawn_doc({"type": "rules", "title": "RULEBOOK - DAY %d" % day,
		"color": PixelTheme.PAPER_PINK, "fields": fields}, null, Color.WHITE, false)
	# Tuck it into the bottom-right corner once its size is known.
	await get_tree().process_frame
	if is_instance_valid(rules_doc):
		rules_doc.position = SCREEN - rules_doc.size - Vector2(4, 4)

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
	hud_rep.add_theme_color_override("font_color", PixelTheme.RED.lightened(0.3) if reputation < 40 else PixelTheme.TEXT_LIGHT)
	hud_res.text = "Residents today %d/%d" % [day_stats.get("residents", 0), rules.quota]
	_refresh_clock()

func _refresh_clock() -> void:
	var minutes := int(8 * 60 + clock / DayRules.DAY_LENGTH_SECONDS * 600)
	hud_clock.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	if clock >= DayRules.DAY_LENGTH_SECONDS:
		hud_clock.text += " CLOSING"

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
	t.tween_property(guest_rect, "position:y", SHEEP_STOP.y - 5, 0.16)
	t.tween_property(guest_rect, "position:y", SHEEP_STOP.y, 0.16)

## Both decisions unlock once the papers are opened.
func _refresh_decision_buttons() -> void:
	var can_decide := state == State.AT_DESK and docs_opened
	accept_btn.disabled = not can_decide
	deny_btn.disabled = not can_decide

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
		win.global_position = (get_global_mouse_position() - _win_grab).round().clamp(
			DOC_BOUNDS.position, SCREEN - win.size)

func _bg(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

func _button(parent: Control, text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(76, 22)
	b.focus_mode = Control.FOCUS_NONE  # so Space never re-presses ACCEPT/DENY
	PixelTheme.tint_button(b, color)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _hud_label(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", PixelTheme.TEXT_LIGHT)
	parent.add_child(l)
	return l

## Text drawn straight over the lobby art needs a dark outline to stay readable.
func _outlined_label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_outline_color", PixelTheme.INK)
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
