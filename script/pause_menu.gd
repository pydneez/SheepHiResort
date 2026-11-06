
extends Control

@onready var pause_button: TextureButton = $Pause
@onready var pause_panel: Control = $PausePanel
@onready var confirm_panel: Control = $ConfirmPanel

@onready var resume_button: Button = $PausePanel/PauseContainer/ResumeButton
@onready var settings_button: Button = $PausePanel/PauseContainer/SettingsButton
@onready var main_menu_button: Button = $PausePanel/PauseContainer/MainMenuButton

@onready var yes_button: Button = $ConfirmPanel/ConfirmContainer/YesButton
@onready var no_button: Button = $ConfirmPanel/ConfirmContainer/NoButton
@onready var back_button: Button = $AudioContainer/BackButton

@onready var audio_panel = $AudioPanel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_panel.hide()

	pause_panel.hide()
	confirm_panel.hide()

	audio_panel.back_pressed.connect(_on_audio_back_pressed)

	get_tree().paused = false

	# Connect all button signals
	pause_button.pressed.connect(_on_pause_button_pressed)
	resume_button.pressed.connect(_on_resume_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	yes_button.pressed.connect(_on_yes_button_pressed)
	no_button.pressed.connect(_on_no_button_pressed)

	print("Pause menu initialized successfully!")


func _on_pause_button_pressed() -> void:
	print("Pause button pressed!")

	pause_panel.show()
	get_tree().paused = true


func _on_resume_button_pressed() -> void:
	audio_panel.hide()
	confirm_panel.hide()
	pause_panel.hide()
	get_tree().paused = false


func _on_settings_button_pressed() -> void:
	pause_panel.hide()
	audio_panel.show()

	# Settings functionality will be implemented later.
	
func _on_audio_back_pressed() -> void:
	audio_panel.hide()
	pause_panel.show()

func _on_main_menu_button_pressed() -> void:
	pause_panel.hide()
	confirm_panel.show()



func _on_no_button_pressed() -> void:
	confirm_panel.hide()
	pause_panel.show()



func _on_yes_button_pressed() -> void:
	print("Yes pressed! Returning to Main Menu.")

	get_tree().paused = false
	GameManager.change_scene("res://scene/main_menu.tscn")
	
	
