
extends UIPackPanel

signal back_pressed

@onready var master_slider: HSlider = $AudioContainer/Master/MasterHSlider
@onready var music_slider: HSlider = $AudioContainer/Music/MusicHSlider
@onready var sfx_slider: HSlider = $AudioContainer/SFX/SFXHSlider
@onready var back_button: Button = $AudioContainer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	master_slider.value = get_volume("Master")
	music_slider.value = get_volume("Music")
	sfx_slider.value = get_volume("SFX")

	back_button.pressed.connect(_on_back_button_pressed)
	master_slider.value_changed.connect(
		func(value): set_volume("Master", value)
	)

	music_slider.value_changed.connect(
		func(value): set_volume("Music", value)
	)

	sfx_slider.value_changed.connect(
		func(value): set_volume("SFX", value)
	)

func _on_back_button_pressed() -> void:
	back_pressed.emit()
	hide()

func get_volume(bus_name: String) -> float:
	var bus_index = AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		return 100.0

	var db = AudioServer.get_bus_volume_db(bus_index)
	return db_to_linear(db) * 100.0


func set_volume(bus_name: String, value: float) -> void:
	var bus_index = AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		push_warning("Audio bus not found: " + bus_name)
		return

	if value <= 0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	else:
		AudioServer.set_bus_volume_db(
			bus_index,
			linear_to_db(value / 100.0)
		)
