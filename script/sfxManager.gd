extends Node

const SFX_FOLDER = "res://assets/SheepHiSFX/"

var sounds: Dictionary = {}
var active_sounds: Dictionary = {}

func _ready() -> void:
	load_sounds()


func load_sounds() -> void:
	var files := ResourceLoader.list_directory(SFX_FOLDER)

	if files.is_empty():
		push_error("No audio files found in: " + SFX_FOLDER)
		return

	for file_name in files:
		if file_name.get_extension().to_lower() == "wav":
			var sound_name := file_name.get_basename()
			var sound_path := SFX_FOLDER + file_name

			var audio := load(sound_path) as AudioStream

			if audio == null:
				push_error("Failed to load audio: " + sound_path)
				continue

			sounds[sound_name] = audio

	print("Loaded ", sounds.size(), " audio files.")

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
