class_name DevMenu
extends CanvasLayer
## Global Developer Console (F1 / F12 or bottom-left button).
## Allows skipping Phase I or Phase II, configuring custom Sheep & Wolf counts
## for Phase II, spawning guests on the fly, jumping to any Day, and previewing
## the Week Report with current stats or specific grades/endings.

var sheep_count: int = 5
var wolf_count: int = 2

var toggle_btn: Button
var panel: PanelContainer
var status_label: Label
var sheep_val_label: Label
var wolf_val_label: Label
var feedback_label: Label

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	layer = 115
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_F12:
			toggle_panel()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	var is_main_menu: bool = scene != null and scene.name == "MainMenu"
	if is_instance_valid(toggle_btn):
		toggle_btn.visible = not is_main_menu
	if panel and panel.visible:
		_refresh_status()

func toggle_panel() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		_refresh_status()

func _build_ui() -> void:
	# 1. Floating bottom-left toggle pill
	toggle_btn = Button.new()
	toggle_btn.text = "DEV [F1]"
	toggle_btn.position = Vector2(14, 1028)
	toggle_btn.custom_minimum_size = Vector2(115, 36)
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.add_theme_stylebox_override("normal", _make_box(Color(0.1, 0.14, 0.2, 0.9), Color(0.4, 0.75, 1.0), 2, 6))
	toggle_btn.add_theme_stylebox_override("hover", _make_box(Color(0.16, 0.24, 0.34, 0.95), Color(0.55, 0.88, 1.0), 2, 6))
	toggle_btn.add_theme_stylebox_override("pressed", _make_box(Color(0.06, 0.09, 0.14, 0.95), Color(0.4, 0.75, 1.0), 2, 6))
	toggle_btn.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	toggle_btn.pressed.connect(toggle_panel)
	add_child(toggle_btn)

	# 2. Main draggable Dev Console Panel
	panel = PanelContainer.new()
	panel.position = Vector2(360, 80)
	panel.custom_minimum_size = Vector2(720, 620)
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _make_box(Color(0.07, 0.1, 0.14, 0.97), Color(0.38, 0.72, 0.95), 3, 12))
	add_child(panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(root_vbox)

	# --- Title Bar (Draggable) ---
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 8)
	root_vbox.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "DEVELOPER CONSOLE — SHEEP HI RESORT  (drag header | F1 to toggle)"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	title_lbl.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_lbl.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	title_lbl.gui_input.connect(_on_title_gui_input)
	title_bar.add_child(title_lbl)

	var close_btn := _make_btn(" ✕ ", Color(0.45, 0.18, 0.18), func(): panel.visible = false)
	close_btn.custom_minimum_size = Vector2(38, 30)
	title_bar.add_child(close_btn)

	# --- Live Status Bar ---
	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _make_box(Color(0.04, 0.06, 0.09), Color(0.22, 0.35, 0.45), 1, 6))
	root_vbox.add_child(status_panel)

	status_label = Label.new()
	status_label.text = "Scene: ... | Day: 1 | Money: $150 | Rep: 70"
	status_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	status_panel.add_child(status_label)

	# --- Section 1: Phase II Pool Config & Skip Phase I ---
	var sec1 := _make_section(root_vbox, "1. PHASE II GUEST POOL & SKIP PHASE I")

	var pool_row := HBoxContainer.new()
	pool_row.add_theme_constant_override("separation", 18)
	sec1.add_child(pool_row)

	# Sheep counter
	var sheep_box := HBoxContainer.new()
	sheep_box.add_theme_constant_override("separation", 4)
	pool_row.add_child(sheep_box)
	var sheep_lbl := Label.new()
	sheep_lbl.text = "Honest Sheep:"
	sheep_lbl.add_theme_color_override("font_color", Color(0.75, 1.0, 0.8))
	sheep_box.add_child(sheep_lbl)
	sheep_box.add_child(_make_small_btn("-5", func(): _adjust_pool(-5, 0)))
	sheep_box.add_child(_make_small_btn("-1", func(): _adjust_pool(-1, 0)))
	sheep_val_label = _make_counter_label(str(sheep_count))
	sheep_box.add_child(sheep_val_label)
	sheep_box.add_child(_make_small_btn("+1", func(): _adjust_pool(1, 0)))
	sheep_box.add_child(_make_small_btn("+5", func(): _adjust_pool(5, 0)))

	# Wolf counter
	var wolf_box := HBoxContainer.new()
	wolf_box.add_theme_constant_override("separation", 4)
	pool_row.add_child(wolf_box)
	var wolf_lbl := Label.new()
	wolf_lbl.text = "Undercover Wolves:"
	wolf_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.72))
	wolf_box.add_child(wolf_lbl)
	wolf_box.add_child(_make_small_btn("-5", func(): _adjust_pool(0, -5)))
	wolf_box.add_child(_make_small_btn("-1", func(): _adjust_pool(0, -1)))
	wolf_val_label = _make_counter_label(str(wolf_count))
	wolf_box.add_child(wolf_val_label)
	wolf_box.add_child(_make_small_btn("+1", func(): _adjust_pool(0, 1)))
	wolf_box.add_child(_make_small_btn("+5", func(): _adjust_pool(0, 5)))

	var skip1_row := HBoxContainer.new()
	skip1_row.add_theme_constant_override("separation", 8)
	sec1.add_child(skip1_row)
	skip1_row.add_child(_make_btn("Skip Phase I - Launch Phase II (Custom Pool)", Color(0.16, 0.44, 0.28), _on_launch_phase2_custom, true))
	skip1_row.add_child(_make_btn("Skip Phase I - End-of-Day Popup", Color(0.22, 0.34, 0.48), _on_skip_phase1_to_eod, true))

	var live_spawn_row := HBoxContainer.new()
	live_spawn_row.add_theme_constant_override("separation", 8)
	sec1.add_child(live_spawn_row)
	var live_lbl := Label.new()
	live_lbl.text = "Live in Phase II:"
	live_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	live_spawn_row.add_child(live_lbl)
	live_spawn_row.add_child(_make_btn("+1 Sheep Now", Color(0.18, 0.38, 0.26), func(): _on_live_spawn(false), true))
	live_spawn_row.add_child(_make_btn("+1 Wolf Now", Color(0.45, 0.2, 0.22), func(): _on_live_spawn(true), true))
	live_spawn_row.add_child(_make_btn("+15s Timer", Color(0.25, 0.32, 0.45), _on_add_phase2_time, true))
	live_spawn_row.add_child(_make_btn("Repair All", Color(0.32, 0.35, 0.2), _on_repair_all_facilities, true))

	# --- Section 2: Skip Phase II & Map Architect ---
	var sec2 := _make_section(root_vbox, "2. SKIP PHASE II & RESORT ARCHITECT")
	var skip2_row := HBoxContainer.new()
	skip2_row.add_theme_constant_override("separation", 8)
	sec2.add_child(skip2_row)
	skip2_row.add_child(_make_btn("Skip Phase II - Finish Rush Hour (Ledger)", Color(0.42, 0.32, 0.14), _on_skip_phase2_to_ledger, true))
	skip2_row.add_child(_make_btn("Skip Phase II - Next Day Front Desk", Color(0.2, 0.36, 0.48), _on_skip_phase2_next_day, true))
	skip2_row.add_child(_make_btn("★ Open Resort Architect", Color(0.16, 0.4, 0.36), _on_open_architect, true))

	# --- Section 3: Week Report & Ending Previews ---
	var sec3 := _make_section(root_vbox, "3. WEEK REPORT & ENDING PREVIEWS")
	var report_row1 := HBoxContainer.new()
	report_row1.add_theme_constant_override("separation", 8)
	sec3.add_child(report_row1)
	report_row1.add_child(_make_btn("Go to Week Report (Current Stats)", Color(0.32, 0.24, 0.48), func(): _on_go_week_report("current"), true))

	var report_row2 := HBoxContainer.new()
	report_row2.add_theme_constant_override("separation", 6)
	sec3.add_child(report_row2)
	report_row2.add_child(_make_btn("★ Grade S", Color(0.42, 0.35, 0.12), func(): _on_go_week_report("S"), true))
	report_row2.add_child(_make_btn("Grade A", Color(0.18, 0.38, 0.24), func(): _on_go_week_report("A"), true))
	report_row2.add_child(_make_btn("Grade B", Color(0.18, 0.32, 0.44), func(): _on_go_week_report("B"), true))
	report_row2.add_child(_make_btn("Grade D", Color(0.36, 0.28, 0.2), func(): _on_go_week_report("D"), true))
	report_row2.add_child(_make_btn("Wolves (F)", Color(0.46, 0.16, 0.18), func(): _on_go_week_report("wolves"), true))
	report_row2.add_child(_make_btn("Fired (F)", Color(0.42, 0.14, 0.26), func(): _on_go_week_report("fired"), true))

	# --- Section 4: Jump to Day, Economy & Front Desk Helpers ---
	var sec4 := _make_section(root_vbox, "4. DAY JUMP, ECONOMY & FRONT DESK CHEATS")

	var day_row := HBoxContainer.new()
	day_row.add_theme_constant_override("separation", 6)
	sec4.add_child(day_row)
	var day_lbl := Label.new()
	day_lbl.text = "Jump to Day:"
	day_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	day_row.add_child(day_lbl)
	for d in range(1, DayRules.LAST_DAY + 1):
		var day_num := d
		day_row.add_child(_make_btn("Day %d" % day_num, Color(0.2, 0.28, 0.38), func(): _on_jump_to_day(day_num), true))

	var econ_row := HBoxContainer.new()
	econ_row.add_theme_constant_override("separation", 6)
	sec4.add_child(econ_row)
	econ_row.add_child(_make_btn("+$100", Color(0.18, 0.38, 0.22), func(): _on_adjust_economy(100, 0), true))
	econ_row.add_child(_make_btn("+$500", Color(0.18, 0.44, 0.24), func(): _on_adjust_economy(500, 0), true))
	econ_row.add_child(_make_btn("★ +20 Rep", Color(0.22, 0.35, 0.46), func(): _on_adjust_economy(0, 20), true))
	econ_row.add_child(_make_btn("★ Max Rep (100)", Color(0.26, 0.38, 0.5), func(): _on_set_rep(100), true))
	econ_row.add_child(_make_btn("? Reveal Desk Guest", Color(0.36, 0.26, 0.44), _on_reveal_desk_guest, true))
	econ_row.add_child(_make_btn("✓ Force Accept", Color(0.16, 0.4, 0.24), func(): _on_force_desk_decision(true), true))
	econ_row.add_child(_make_btn("✕ Force Deny", Color(0.44, 0.18, 0.18), func(): _on_force_desk_decision(false), true))

	# --- Footer Feedback Label ---
	feedback_label = Label.new()
	feedback_label.text = "Ready. Use any button above to control game flow."
	feedback_label.add_theme_color_override("font_color", Color(0.65, 0.92, 0.75))
	root_vbox.add_child(feedback_label)

# =============================================================================
# Actions & Callbacks

func _adjust_pool(dsheep: int, dwolf: int) -> void:
	sheep_count = clampi(sheep_count + dsheep, 0, 40)
	wolf_count = clampi(wolf_count + dwolf, 0, 25)
	sheep_val_label.text = " %d " % sheep_count
	wolf_val_label.text = " %d " % wolf_count
	_notify("Configured Phase II pool: %d honest sheep, %d wolves." % [sheep_count, wolf_count])

func _on_launch_phase2_custom() -> void:
	_sync_desk_if_active()
	GameManager.is_layout_edit_mode = false
	GameManager.build_custom_phase2_pool(sheep_count, wolf_count)
	_notify("Launching Phase II with %d sheep and %d wolves..." % [sheep_count, wolf_count])
	panel.visible = false
	GameManager.change_scene("res://scene/phase2_resort.tscn")

func _on_skip_phase1_to_eod() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("end_day"):
		if GameManager.admitted_guests.is_empty():
			GameManager.build_custom_phase2_pool(sheep_count, wolf_count)
		scene.end_day()
		panel.visible = false
		_notify("Skipped Phase I to End-of-Day summary.")
	else:
		_notify("Not currently on Front Desk — switching to Front Desk first.")
		GameManager.is_layout_edit_mode = false
		GameManager.change_scene("res://scene/front_desk.tscn")

func _on_live_spawn(is_wolf: bool) -> void:
	var scene := get_tree().current_scene
	if scene is Phase2Resort and not GameManager.is_layout_edit_mode:
		var data := GameManager.make_dev_guest(is_wolf)
		GameManager.record_admitted_guest(data)
		scene.spawn_guest_from_data(data)
		_notify("Spawned +1 %s at the Resort entrance!" % ("Undercover Wolf" if is_wolf else "Honest Sheep"))
	else:
		_adjust_pool(0 if is_wolf else 1, 1 if is_wolf else 0)
		_notify("Added +1 %s to pool (launch Phase II to spawn)." % ("wolf" if is_wolf else "sheep"))

func _on_add_phase2_time() -> void:
	var scene := get_tree().current_scene
	if scene is Phase2Resort and scene.is_active:
		scene.time_left += 15.0
		scene._refresh_hud()
		_notify("Added +15s to Phase II Rush Hour timer.")
	else:
		_notify("Phase II Rush Hour is not currently active.")

func _on_repair_all_facilities() -> void:
	var scene := get_tree().current_scene
	if scene is Phase2Resort:
		var fixed := 0
		for f in scene.facilities:
			if is_instance_valid(f) and f.is_broken:
				f.repair()
				fixed += 1
		_notify("Repaired %d broken facilities." % fixed)
	else:
		_notify("Only available while in Phase II Resort.")

func _on_skip_phase2_to_ledger() -> void:
	var scene := get_tree().current_scene
	if scene is Phase2Resort and not GameManager.is_layout_edit_mode:
		if scene.is_active:
			scene.time_left = 0.0
			scene._end_rush_hour()
		panel.visible = false
		_notify("Finished Phase II Rush Hour and opened ledger.")
	else:
		_notify("Not in active Phase II Rush Hour — launching Phase II first.")
		_on_launch_phase2_custom()

func _on_skip_phase2_next_day() -> void:
	var scene := get_tree().current_scene
	if scene is Phase2Resort and not GameManager.is_layout_edit_mode:
		if scene.is_active:
			scene._end_rush_hour()
		scene._on_next_day_pressed()
		panel.visible = false
	else:
		_sync_desk_if_active()
		GameManager.current_day = clampi(GameManager.current_day + 1, 1, DayRules.LAST_DAY)
		GameManager.reset_day_pool()
		GameManager.is_layout_edit_mode = false
		panel.visible = false
		GameManager.change_scene("res://scene/front_desk.tscn")

func _on_open_architect() -> void:
	_sync_desk_if_active()
	GameManager.is_layout_edit_mode = true
	panel.visible = false
	GameManager.change_scene("res://scene/phase2_resort.tscn")

func _on_go_week_report(preset: String) -> void:
	_sync_desk_if_active()
	GameManager.is_layout_edit_mode = false
	var ending := ""
	match preset:
		"S":
			GameManager.current_day = DayRules.LAST_DAY
			GameManager.wolves_admitted_total = 0
			GameManager.reputation = 95
			GameManager.week = {"processed": 35, "correct": 35, "wolves_caught": 8, "residents": 27, "quota_days": DayRules.LAST_DAY, "earned": 420}
			ending = ""
		"A":
			GameManager.current_day = DayRules.LAST_DAY
			GameManager.wolves_admitted_total = 1
			GameManager.reputation = 80
			GameManager.week = {"processed": 35, "correct": 31, "wolves_caught": 7, "residents": 24, "quota_days": 6, "earned": 350}
			ending = ""
		"B":
			GameManager.current_day = DayRules.LAST_DAY
			GameManager.wolves_admitted_total = 2
			GameManager.reputation = 65
			GameManager.week = {"processed": 35, "correct": 26, "wolves_caught": 5, "residents": 20, "quota_days": 5, "earned": 260}
			ending = ""
		"D":
			GameManager.current_day = DayRules.LAST_DAY
			GameManager.wolves_admitted_total = 2
			GameManager.reputation = 45
			GameManager.week = {"processed": 35, "correct": 20, "wolves_caught": 3, "residents": 15, "quota_days": 3, "earned": 160}
			ending = ""
		"wolves":
			GameManager.wolves_admitted_total = 3
			ending = "wolves"
		"fired":
			GameManager.reputation = 0
			ending = "fired"
		_:
			ending = ""

	panel.visible = false
	var scene := get_tree().current_scene
	if scene and scene.has_method("trigger_dev_week_report"):
		if preset != "current":
			scene._restore_from_game_manager()
			scene.day = GameManager.current_day
		scene.trigger_dev_week_report(ending)
	else:
		GameManager.dev_pending_week_report = {"ending": ending}
		GameManager.change_scene("res://scene/front_desk.tscn")

func _on_jump_to_day(d: int) -> void:
	_sync_desk_if_active()
	GameManager.current_day = clampi(d, 1, DayRules.LAST_DAY)
	GameManager.run_started = true
	GameManager.is_layout_edit_mode = false
	panel.visible = false
	var scene := get_tree().current_scene
	if scene and scene.has_method("start_day"):
		scene.start_day(GameManager.current_day)
	else:
		GameManager.change_scene("res://scene/front_desk.tscn")

func _on_adjust_economy(dmoney: int, drep: int) -> void:
	var scene := get_tree().current_scene
	if scene and "money" in scene and "reputation" in scene:
		scene.money += dmoney
		scene.reputation = clampi(scene.reputation + drep, 0, 100)
		if scene.has_method("_refresh_hud"):
			scene._refresh_hud()
		if scene.has_method("_sync_to_game_manager"):
			scene._sync_to_game_manager()
	else:
		GameManager.money += dmoney
		GameManager.reputation = clampi(GameManager.reputation + drep, 0, 100)
	_refresh_status()
	_notify("Adjusted economy: %+$d, %+d rep." % [dmoney, drep])

func _on_set_rep(val: int) -> void:
	var scene := get_tree().current_scene
	if scene and "reputation" in scene:
		scene.reputation = clampi(val, 0, 100)
		if scene.has_method("_refresh_hud"):
			scene._refresh_hud()
		if scene.has_method("_sync_to_game_manager"):
			scene._sync_to_game_manager()
	else:
		GameManager.reputation = clampi(val, 0, 100)
	_refresh_status()
	_notify("Reputation set to %d." % val)

func _on_reveal_desk_guest() -> void:
	var scene := get_tree().current_scene
	if scene and "guest" in scene and not scene.guest.is_empty():
		var g: Dictionary = scene.guest
		var is_w: bool = g.get("is_wolf", false)
		var flaws: Array = g.get("flaws", [])
		var tell: String = g.get("appearance", {}).get("tell", "")
		var info := "GUEST: %s | %s | Flaws: %s | Tell: %s" % [
			g.get("truth", {}).get("name", "?"),
			"WOLF!" if is_w else "Honest Sheep",
			", ".join(PackedStringArray(flaws)) if not flaws.is_empty() else "None (Valid)",
			tell if tell != "" else "None"
		]
		_notify(info)
		if scene.has_method("_toast"):
			scene._toast(info, Color(1, 0.45, 0.45) if is_w or not flaws.is_empty() else Color(0.5, 1, 0.6))
	else:
		_notify("No guest is currently at the Front Desk (ring the bell first).")

func _on_force_desk_decision(accept: bool) -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("decide") and "state" in scene:
		if scene.state == scene.State.IDLE:
			scene._on_bell()
			_notify("Rang the bell! Click Force Accept/Deny once guest arrives.")
			return
		if scene.state == scene.State.AT_DESK:
			if not scene.docs_opened:
				scene._on_pile_clicked()
			scene.decide(accept)
			_notify("Forced %s on current guest." % ("ACCEPT" if accept else "DENY"))
		else:
			_notify("Wait for guest to finish walking.")
	else:
		_notify("Only available at the Front Desk.")

func _sync_desk_if_active() -> void:
	var scene := get_tree().current_scene
	if scene and scene.has_method("_sync_to_game_manager"):
		scene._sync_to_game_manager()

func _refresh_status() -> void:
	var scene := get_tree().current_scene
	var scene_name := "Unknown"
	var d := GameManager.current_day
	var m := GameManager.money
	var r := GameManager.reputation
	if scene:
		if scene is Phase2Resort:
			scene_name = "Resort Architect" if GameManager.is_layout_edit_mode else "Phase II: Resort Rush"
		elif scene.has_method("decide"):
			scene_name = "Phase I: Front Desk"
			d = scene.day
			m = scene.money
			r = scene.reputation
	status_label.text = "%s   |   Day %d/%d   |   $%d   |   ★ Rep %d   |   Pool: %d guests (%d wolves)" % [
		scene_name, d, DayRules.LAST_DAY, m, r, GameManager.admitted_guests.size(), GameManager.wolves_in_pool
	]

func _notify(msg: String) -> void:
	if feedback_label:
		feedback_label.text = "> " + msg

func _on_title_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = panel.get_global_mouse_position() - panel.global_position
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var vp_size := get_viewport().get_visible_rect().size
		panel.global_position = (panel.get_global_mouse_position() - _drag_offset).clamp(
			Vector2.ZERO, vp_size - panel.size
		)

# =============================================================================
# UI Helpers

func _make_section(parent: Control, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _make_box(Color(0.11, 0.15, 0.21), Color(0.24, 0.36, 0.48), 1, 8))
	parent.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	vb.add_child(lbl)
	return vb

func _make_btn(text: String, bg: Color, cb: Callable, expand := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _make_box(bg, bg.lightened(0.35), 1, 6))
	b.add_theme_stylebox_override("hover", _make_box(bg.lightened(0.12), bg.lightened(0.5), 1, 6))
	b.add_theme_stylebox_override("pressed", _make_box(bg.darkened(0.18), bg.lightened(0.25), 1, 6))
	b.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	b.pressed.connect(cb)
	return b

func _make_small_btn(text: String, cb: Callable) -> Button:
	var b := _make_btn(text, Color(0.2, 0.28, 0.38), cb, false)
	b.custom_minimum_size = Vector2(36, 28)
	return b

func _make_counter_label(text: String) -> Label:
	var l := Label.new()
	l.text = " " + text + " "
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(38, 28)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	return l

func _make_box(bg: Color, border: Color, bw: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(5)
	s.set_content_margin_all(pad)
	return s
