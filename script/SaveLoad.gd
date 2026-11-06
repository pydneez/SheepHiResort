
extends Node

const FILE_PATH: String = "user://SaveFile.save"

func _ready() -> void:
	print("SaveLoad initialized.")
	print("Save path: ", ProjectSettings.globalize_path(FILE_PATH))
	load_game()


func save_game() -> void:
	var save_data: Dictionary = GameManager.get_save_data()

	print("Attempting to save...")
	print("Save path: ", ProjectSettings.globalize_path(FILE_PATH))

	var file := FileAccess.open(FILE_PATH, FileAccess.WRITE)

	if file == null:
		push_error("Failed to save game! Error: " + str(FileAccess.get_open_error()))
		return

	file.store_var(save_data)
	file.close()

	print("Save successful!")
	print("File exists: ", FileAccess.file_exists(FILE_PATH))
	
	file.store_var(save_data)
	file.close()

	print("Game saved successfully!")
	print("Save path: ", ProjectSettings.globalize_path(FILE_PATH))
	print("File exists after saving: ", FileAccess.file_exists(FILE_PATH))


func load_game() -> void:
	print("Attempting to load...")
	print("Save path: ", ProjectSettings.globalize_path(FILE_PATH))
	print("File exists: ", FileAccess.file_exists(FILE_PATH))

	if not FileAccess.file_exists(FILE_PATH):
		print("No existing save file.")
		return

	var file := FileAccess.open(FILE_PATH, FileAccess.READ)

	if file == null:
		push_error("Failed to load save file! Error: " + str(FileAccess.get_open_error()))
		return

	var data = file.get_var()
	file.close()

	if data is Dictionary:
		GameManager.load_save_data(data)
		print("Game loaded successfully!")
	else:
		push_error("Save file exists, but its contents are invalid.")


func delete_save() -> void:
	if FileAccess.file_exists(FILE_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(FILE_PATH)
		)
		print("Previous save deleted.")
