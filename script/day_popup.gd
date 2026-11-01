class_name DayPopup
extends ColorRect
## Morning briefing and end-of-day text (scene/day_popup.tscn).

signal continue_pressed

@onready var _text: RichTextLabel = %Text
@onready var _button: Button = %ContinueButton

func _ready() -> void:
	_button.pressed.connect(func():
		visible = false
		continue_pressed.emit())

func show_text(bbcode: String, button_text: String) -> void:
	_text.text = bbcode
	_button.text = button_text
	visible = true
	move_to_front()
