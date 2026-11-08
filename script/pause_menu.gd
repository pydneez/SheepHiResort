extends Control

@onready var pause_button: TextureButton = $Pause
@onready var pause_panel: Control = $PausePanel
@onready var confirm_panel: Control = $ConfirmPanel

@onready var resume_button: Button = $PausePanel/PauseContainer/ResumeButton
@onready var settings_button: Button = $PausePanel/PauseContainer/SettingsButton
@onready var main_menu_button: Button = $PausePanel/PauseContainer/MainMenuButton

@onready var yes_button: Button = $ConfirmPanel/ConfirmContainer/YesButton
@onready var no_button: Button = $ConfirmPanel/ConfirmContainer/NoButton
@onready var back_button: Button = $AudioPanel/AudioContainer/BackButton

@onready var audio_panel = $AudioPanel

@onready var ledger_panel: Control = get_node_or_null("../LedgerPanel")

@export var click_sound: AudioStream

@onready var computer_window: Control = get_node_or_null("../ComputerWindow")

var computer_mouse_filters: Dictionary = {}
var ledger_mouse_filters: Dictionary = {}

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

	if is_instance_valid(ledger_panel):
		_disable_ledger_mouse_input(ledger_panel)

	if is_instance_valid(computer_window):
		_disable_computer_mouse_input(computer_window)

	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.z_index = 100
	pause_panel.show()

	get_tree().paused = true
	SfxManager.play_sfx("Button_Press", "SFX")

func _on_resume_button_pressed() -> void:
	audio_panel.hide()
	confirm_panel.hide()
	pause_panel.hide()
	SfxManager.play_sfx("Button_hover", "SFX")
	_restore_ledger_mouse_input()
	_restore_computer_mouse_input()

	get_tree().paused = false


func _on_settings_button_pressed() -> void:
	pause_panel.hide()
	audio_panel.z_index = 101
	audio_panel.show()
	SfxManager.play_sfx("Button_Press", "SFX")

	# Settings functionality will be implemented later.
	
func _on_audio_back_pressed() -> void:
	SfxManager.play_sfx("Button_hover", "SFX")
	audio_panel.hide()
	pause_panel.show()

func _on_main_menu_button_pressed() -> void:
	pause_panel.hide()
	confirm_panel.show()
	confirm_panel.z_index = 101
	SfxManager.play_sfx("Button_Press", "SFX")


func _on_no_button_pressed() -> void:
	confirm_panel.hide()
	pause_panel.show()
	SfxManager.play_sfx("Button_hover", "SFX")

func _on_yes_button_pressed() -> void:
	print("Yes pressed! Returning to Main Menu.")
	SfxManager.play_sfx("Button_Press", "SFX")
	get_tree().paused = false
	GameManager.change_scene("res://scene/main_menu.tscn")
	SfxManager.stop_all_sfx()

			
func _disable_ledger_mouse_input(node: Node) -> void:
	if node == null:
		return

	if node is Control:
		ledger_mouse_filters[node] = node.mouse_filter
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in node.get_children():
		_disable_ledger_mouse_input(child)
		
func _restore_ledger_mouse_input() -> void:
	for node in ledger_mouse_filters:
		if is_instance_valid(node):
			node.mouse_filter = ledger_mouse_filters[node]

	ledger_mouse_filters.clear()

func _disable_computer_mouse_input(node: Node) -> void:
	if node == null:
		return

	if node is Control:
		computer_mouse_filters[node] = node.mouse_filter
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in node.get_children():
		_disable_computer_mouse_input(child)


func _restore_computer_mouse_input() -> void:
	for node in computer_mouse_filters:
		if is_instance_valid(node):
			node.mouse_filter = computer_mouse_filters[node]

	computer_mouse_filters.clear()
