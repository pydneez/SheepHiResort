extends Node

const SFX_FOLDER = "res://assets/SheepHiSFX/"

var sounds: Dictionary = {}
var active_sounds: Dictionary = {}

func _ready() -> void:
	load_sounds()


func load_sounds() -> void:
	var directory := DirAccess.open(SFX_FOLDER)

	if directory == null:
		push_error("Could not open SFX folder: " + SFX_FOLDER)
		return

	directory.list_dir_begin()

	var file_name := directory.get_next()

	while file_name != "":
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "wav":
			var sound_name := file_name.get_basename()
			var sound_path := SFX_FOLDER + file_name

			sounds[sound_name] = load(sound_path)

		file_name = directory.get_next()

	directory.list_dir_end()

	print("Loaded ", sounds.size(), " SFX files.")


func play_sfx(
	sound_name: String,
	bus: String = "SFX",
	volume_db: float = 0.0
) -> void:
	if not sounds.has(sound_name):
		push_warning("Sound not found: " + sound_name)
		return

	var player := AudioStreamPlayer.new()
	player.stream = sounds[sound_name]
	player.bus = bus
	player.volume_db = volume_db

	add_child(player)

	if not active_sounds.has(sound_name):
		active_sounds[sound_name] = []

	active_sounds[sound_name].append(player)

	player.finished.connect(func():
		if active_sounds.has(sound_name):
			active_sounds[sound_name].erase(player)

			if active_sounds[sound_name].is_empty():
				active_sounds.erase(sound_name)

		player.queue_free()
	)

	player.play()
	
func stop_sfx(sound_name: String) -> void:
	if not active_sounds.has(sound_name):
		return

	for player in active_sounds[sound_name]:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()

	active_sounds.erase(sound_name)

func stop_all_sfx() -> void:
	for sound_name in active_sounds.keys():
		stop_sfx(sound_name)
