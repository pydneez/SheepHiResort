class_name MainMenu
extends Control
## Main Menu scene for Sheep Hi Resort.
## Features:
## - Fullscreen Menu_bg.png background
## - Logo at the top right
## - 4 distinct TextureButtons (Play, Load Game, Options, Quit) with normal and pressed textures
## - Smooth scene transition to Front Desk (game start) or quit

@onready var play_button: TextureButton = $ButtonsContainer/Row1/PlayButton
@onready var load_button: TextureButton = $ButtonsContainer/Row1/LoadButton
@onready var options_button: TextureButton = $ButtonsContainer/Row2/OptionsButton
@onready var quit_button: TextureButton = $ButtonsContainer/Row2/QuitButton
@onready var audio_panel = $AudioPanel



func _ready() -> void:
	SfxManager.play_sfx("Menutheme", "Music")
	play_button.pressed.connect(_on_play_pressed)
	load_button.pressed.connect(_on_load_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	audio_panel.hide()
	audio_panel.back_pressed.connect(_on_audio_back_pressed)
	


func _on_play_pressed() -> void:
	
	GameManager.start_new_game()
	SfxManager.play_sfx("Button_Press", "SFX")
	# Remove the previous save so a fresh game doesn't accidentally
	# load the old run on the next launch.
	SaveLoad.delete_save()
	GameManager.change_scene("res://scene/front_desk.tscn")

func _on_load_pressed() -> void:
	if not SaveLoad.load_game():
		GameManager.start_new_game()
	SfxManager.play_sfx("Button_Press", "SFX")
	GameManager.change_scene("res://scene/front_desk.tscn")
	

func _on_options_pressed() -> void:
	# Placeholder for settings/options
	#print("Settings pressed!")
	audio_panel.show()
	SfxManager.play_sfx("Button_Press", "SFX")
	
	
func _on_audio_back_pressed() -> void:
	SfxManager.play_sfx("Button_hover", "SFX")
	audio_panel.hide()
	
	
func _on_quit_pressed() -> void:
	get_tree().quit()
	SfxManager.play_sfx("Button_Press", "SFX")
