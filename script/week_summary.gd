class_name WeekSummary
extends Control
## End-of-week grade screen (scene/week_summary.tscn). Only shows a result;
## the grade itself is decided in front_desk.gd.

signal play_again

@onready var _title: Label = %Title
@onready var _stats: Label = %Stats
@onready var _grade: TextureRect = %Grade
@onready var _reaction: TextureRect = %Reaction
@onready var _quote: Label = %Quote

func _ready() -> void:
	%PlayAgain.pressed.connect(func():
		visible = false
		play_again.emit())

## grade: "S", "A", "B", "D" or "F" (picks grade_x.png and reaction_x.png).
func show_result(grade: String, title: String, stats: String, quote: String) -> void:
	_grade.texture = load("res://assets/grade_%s.png" % grade.to_lower())
	_reaction.texture = load("res://assets/reaction_%s.png" % grade.to_lower())
	_title.text = title
	_stats.text = stats
	_quote.text = "\"%s\"" % quote
	visible = true
	move_to_front()
