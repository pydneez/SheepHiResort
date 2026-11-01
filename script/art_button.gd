class_name ArtButton
extends TextureButton
## Clickable desk art (bell, paper pile, ACCEPT / DENY). Only the visible pixels
## of the picture react to the mouse, not its empty corners.

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE  # so Space never re-presses ACCEPT/DENY
	_update_click_mask()

## Swap the picture (e.g. a different paper pile); the click area follows it.
func set_art(tex: Texture2D) -> void:
	texture_normal = tex
	_update_click_mask()

## Locked buttons can't be pressed and are shown dimmed.
func set_locked(locked: bool) -> void:
	disabled = locked
	modulate = Color(0.55, 0.55, 0.55) if locked else Color.WHITE

func _update_click_mask() -> void:
	if texture_normal == null:
		return
	var mask := BitMap.new()
	mask.create_from_image_alpha(texture_normal.get_image())
	texture_click_mask = mask
