class_name SheepLook
extends Control
## One sheep built from stacked part pictures (scene/sheep_look.tscn). Used for
## the guest at the desk and, cropped to the head, for the ID-card photo.
##
## A look is a Dictionary:
##   {"base": "01", "wolf_skin": false, "wolf_detail": false,
##    "parts": {"eyes": "eyes_01", "hat": "hat_02", ...},
##    "wool": "Cream", "skin": "Pink-beige", "outfit": "Seaside"}

const RECOLOUR_SHADER := preload("res://shaders/sheep_part.gdshader")
## Layers back to front; the base sheep is three layers.
const LAYERS := ["back", "base_wool", "base_skin", "base_detail", "bottom", "top",
	"ears", "eyes", "mouth", "headwool", "hat", "front"]

## The look currently shown (see show_look).
var look_data := {}
var _layers := {}   # layer name -> TextureRect (each with a "Detail" child)

func _ready() -> void:
	for layer in LAYERS:
		var r := _picture(layer)
		add_child(r)
		var detail := _picture("Detail")   # fixed-colour bits drawn right on top of the part
		r.add_child(detail)
		_layers[layer] = r

func show_look(look: Dictionary) -> void:
	look_data = look
	var cat := SheepParts.shared()
	var colours := SheepColours.shared()
	for layer in _layers:
		_set_layer(layer, "", null, "")
	var b: Dictionary = cat.bases.get(look.get("base", ""), {})
	if b.is_empty():
		push_warning("SheepLook: unknown base '%s'" % look.get("base", ""))
		return
	var wolf_skin: bool = look.get("wolf_skin", false) and b.has("wolf_skin")
	var wolf_detail: bool = look.get("wolf_detail", false) and b.has("wolf_detail")
	_set_layer("base_wool", b.wool, colours.wool(look.wool), "")
	_set_layer("base_skin", b.wolf_skin if wolf_skin else b.skin, null if wolf_skin else colours.skin(look.skin), "")
	_set_layer("base_detail", b.wolf_detail if wolf_detail else b.detail, null, "")
	var outfit := colours.outfit(look.get("outfit", ""))
	for slot in look.get("parts", {}):
		var part := cat.part(slot, look.parts[slot])
		if part.is_empty():
			push_warning("SheepLook: unknown part '%s'" % look.parts[slot])
			continue
		_set_layer(slot, part.path, _ramp_for(slot, part, look, colours, outfit), part.detail)

## Mirror the sheep (walking away to the left).
func set_flipped(flipped: bool) -> void:
	scale.x = -absf(scale.x) if flipped else absf(scale.x)

func _ramp_for(slot: String, part: Dictionary, look: Dictionary, colours: SheepColours, outfit: OutfitSet) -> ColourRamp:
	if not SheepParts.recolours(slot, part):
		return null
	match SheepParts.RECOLOUR[slot]:
		"wool":
			return colours.wool(look.wool)
		"skin":
			return colours.skin(look.skin)
	if outfit == null:
		return null
	return outfit.get(SheepParts.RECOLOUR[slot])   # top / accent / bottom

func _set_layer(layer: String, path: String, ramp: ColourRamp, detail_path: String) -> void:
	var r: TextureRect = _layers[layer]
	r.texture = load(path) if path != "" else null
	r.material = null
	if ramp != null:
		var m := ShaderMaterial.new()
		m.shader = RECOLOUR_SHADER
		m.set_shader_parameter("highlight", ramp.highlight)
		m.set_shader_parameter("base_colour", ramp.base)
		m.set_shader_parameter("shadow", ramp.shadow)
		m.set_shader_parameter("deep", ramp.deep)
		r.material = m
	var detail: TextureRect = r.get_node("Detail")
	detail.texture = load(detail_path) if detail_path != "" else null

func _picture(node_name: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	r.size = Vector2(SheepParts.CANVAS)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
