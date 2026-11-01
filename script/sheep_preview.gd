extends Control
## Sheep preview (scene/sheep_preview.tscn): open it in the editor and press F6
## to see a grid of random sheep built from the current parts and colour lists.
## "New batch" rolls new ones; "Wolves" shows wolves with their giveaway, and
## each wolf's ID photo (how its forged papers show it) next to it.

const LOOK_SCENE := preload("res://scene/sheep_look.tscn")
const COLUMNS := 6
const CELL := Vector2(232, 360)
const LOOK_SCALE := 0.62

var _seed := 1
var _wolves := false
var _grid: Control
var _info: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("e8dcc4")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 10)
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)
	var again := Button.new()
	again.text = "New batch"
	again.pressed.connect(func():
		_seed += 1
		_refresh())
	bar.add_child(again)
	var wolves := CheckButton.new()
	wolves.text = "Wolves (with their ID photo)"
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		wolves.add_theme_color_override(c, Color("3a2a20"))
	wolves.toggled.connect(func(on):
		_wolves = on
		_refresh())
	bar.add_child(wolves)
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color("3a2a20"))
	bar.add_child(_info)
	_grid = Control.new()
	_grid.position = Vector2(0, 56)
	add_child(_grid)
	_refresh()

func _refresh() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var gen := SheepGenerator.new(_seed, DayRules.for_day(DayRules.LAST_DAY))
	var cat := SheepParts.shared()
	_info.text = "batch %d   ·   parts from %s" % [_seed, cat.root]
	var wools := SheepColours.shared().wool_names()
	var tells := gen.wolf_tells()
	var cells := []
	for i in COLUMNS * 2:
		var wool: String = gen.pick(wools)
		if _wolves and not tells.is_empty():
			if i % 2 == 1:
				continue   # odd cells hold the previous wolf's ID photo
			var look := gen.make_look(wool, gen.pick(tells))
			cells.append([look, "WOLF at the desk"])
			cells.append([gen.claimed_look(look, wool), "its ID photo"])
		else:
			cells.append([gen.make_look(wool), ""])
	for i in cells.size():
		var cell := Vector2((i % COLUMNS) * CELL.x + 8, (i / COLUMNS) * CELL.y)
		var look: Dictionary = cells[i][0]
		var sheep: SheepLook = LOOK_SCENE.instantiate()
		_grid.add_child(sheep)
		sheep.pivot_offset = Vector2.ZERO
		sheep.scale = Vector2.ONE * LOOK_SCALE
		sheep.position = cell
		sheep.show_look(look)
		var label := Label.new()
		label.text = "%s wool · %s skin\n%s%s" % [look.wool, look.skin, look.outfit,
			("\n" + cells[i][1]) if cells[i][1] != "" else ""]
		label.position = cell + Vector2(0, SheepParts.CANVAS.y * LOOK_SCALE + 2)
		label.size = Vector2(CELL.x - 12, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("3a2a20"))
		_grid.add_child(label)
