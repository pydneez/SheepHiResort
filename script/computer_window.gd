class_name ComputerWindow
extends PanelContainer
## The reservations window (scene/computer_window.tscn): today's bookings with
## search. Drag it by its title; right-click a value to compare it.

signal field_clicked(field: Dictionary, label: Control)

const DRAG_BOUNDS := Rect2(0, 48, 1440, 1032)   # anywhere below the top bar

var _bookings: Array = []
var _rules: Dictionary = {}
var _grab := Vector2.ZERO

@onready var _search: LineEdit = %Search
@onready var _list: ItemList = %BookingList
@onready var _count: Label = %BookingCount
@onready var _details: GridContainer = %Details

func _ready() -> void:
	%Title.gui_input.connect(_on_title_input)
	%CloseButton.pressed.connect(hide)
	_search.text_changed.connect(func(_t): _refresh())
	_list.item_selected.connect(_on_booking_selected)
	_count.gui_input.connect(_on_count_input)

## Load a new day's bookings. rules decides which booking fields are shown.
func show_bookings(bookings: Array, rules: Dictionary) -> void:
	_bookings = bookings
	_rules = rules
	_search.text = ""
	_refresh()

func toggle() -> void:
	visible = not visible
	if visible:
		move_to_front()

func _refresh() -> void:
	_list.clear()
	var q := _search.text.strip_edges().to_lower()
	for b in _bookings:
		if q == "" or b.name.to_lower().contains(q) or b.id.to_lower().contains(q):
			var idx := _list.add_item("%s  %s" % [b.id, b.name])
			_list.set_item_metadata(idx, b)
	_count.text = "Today's bookings: %d  [right-click]" % _bookings.size()
	_clear_details()

func _clear_details() -> void:
	for c in _details.get_children():
		c.queue_free()

func _on_booking_selected(idx: int) -> void:
	_clear_details()
	var b: Dictionary = _list.get_item_metadata(idx)
	var fields := [
		SheepGenerator._f("Name", "name", b.name), SheepGenerator._f("ID", "id", b.id),
		SheepGenerator._f("Region", "region", b.region), SheepGenerator._f("Species", "species", b.species)]
	if _rules.get("check_wool", false):
		fields.append(SheepGenerator._f("Wool", "wool", b.wool))
	if _rules.get("check_voucher", false):
		fields.append(SheepGenerator._f("Room", "room", b.room))
		fields.append(SheepGenerator._f("Nights", "nights", b.nights))
	for f in fields:
		var k := Label.new()
		k.text = f.label + ":"
		k.add_theme_color_override("font_color", Color(0.5, 0.75, 0.7))
		_details.add_child(k)
		var v := DeskDocument.make_field_label(f, "db")
		v.add_theme_color_override("font_color", Color(0.85, 1, 0.95))
		v.mouse_filter = Control.MOUSE_FILTER_STOP
		v.gui_input.connect(func(e):
			if DeskDocument.is_compare_click(e):
				field_clicked.emit(f, v))
		_details.add_child(v)

## Right-click "Today's bookings", then an ID, to check the guest is booked today.
func _on_count_input(event: InputEvent) -> void:
	if DeskDocument.is_compare_click(event):
		var ids := _bookings.map(func(b): return b.id)
		field_clicked.emit({"label": "Bookings", "kind": "booking_list", "value": ids,
			"text": "bookings", "source": "db"}, _count)

func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_grab = get_global_mouse_position() - global_position
		move_to_front()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		global_position = (get_global_mouse_position() - _grab).clamp(
			DRAG_BOUNDS.position, DRAG_BOUNDS.end - size)
