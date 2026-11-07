class_name SheepFace
extends Resource
## One face of a SheepCharacter. The picture is usually an AtlasTexture: a box
## cut out of the character sheet (Inspector > Texture > Edit Region).

## Unique within the character, e.g. "face_02" or "wolf_01".
@export var id := ""
## Leave empty for "nothing on top of the body" (e.g. the rapper without glasses).
@export var texture: Texture2D
## A wolf giveaway (red eyes): only wolves wear it, never shown on an ID photo.
@export var wolf := false
## Extra nudge for this face only, on top of the character's face_anchor.
@export var offset := Vector2.ZERO
