class_name SpeechBubble
extends PanelContainer
## What the guest says (scene/speech_bubble.tscn). Grows taller for long lines.

@onready var _text: Label = %Text

func say(text: String) -> void:
	_text.text = text
	visible = true
