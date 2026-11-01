@tool
class_name ColourRamp
extends Resource
## One colour for a recolourable sheep part, as 4 shades. The game swaps the
## part's 4 greys for these: #ffffff -> highlight, #c0c0c0 -> base,
## #808080 -> shadow, #404040 -> deep. Edit them with the colour pickers in the
## Inspector (data/sheep_colours.tres).

@export var name := ""
## Wool/skin: light, mid or dark. Outfit colours don't use the tag.
@export_enum("light", "mid", "dark") var tag := "light"
@export var highlight := Color.WHITE
@export var base := Color(0.75, 0.75, 0.75)
@export var shadow := Color(0.5, 0.5, 0.5)
@export var deep := Color(0.25, 0.25, 0.25)

static func make(ramp_name: String, ramp_tag: String, hexes: Array) -> ColourRamp:
	var r := ColourRamp.new()
	r.name = ramp_name
	r.tag = ramp_tag
	r.highlight = Color(hexes[0])
	r.base = Color(hexes[1])
	r.shadow = Color(hexes[2])
	r.deep = Color(hexes[3])
	return r

## The 4 shades from light to dark, as the recolour shader wants them.
func shades() -> PackedColorArray:
	return PackedColorArray([highlight, base, shadow, deep])
