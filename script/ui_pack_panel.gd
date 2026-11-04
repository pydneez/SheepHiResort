class_name UIPackPanel
extends PanelContainer
## Reusable scene/control component backed by `res://assets/UI/UI_pack.png`.
## Drop `res://scene/ui_pack_panel.tscn` into any scene and select `panel_variant`
## in the Inspector to switch between UI_pack.png 9-slice styles.

@export_enum(
	"beige_raised",
	"beige_flat",
	"beige_inset",
	"cream_raised",
	"cream_flat",
	"cream_inset",
	"tan_raised",
	"tan_flat",
	"tan_inset",
	"brown_raised",
	"brown_flat",
	"brown_inset",
	"wood_frame_light",
	"wood_frame_medium",
	"wood_frame_dark",
	"banner",
	"speech_bubble"
) var panel_variant: String = "beige_raised":
	set(value):
		panel_variant = value
		_apply_style()

@export var content_margins: Vector4 = Vector4(14, 12, 14, 14):
	set(value):
		content_margins = value
		_apply_style()

@export var panel_tint: Color = Color.WHITE:
	set(value):
		panel_tint = value
		_apply_style()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_style()

func _apply_style() -> void:
	UIPack.style_panel(self, panel_variant, content_margins, panel_tint)
