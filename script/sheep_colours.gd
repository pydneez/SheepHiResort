@tool
class_name SheepColours
extends Resource
## The curated colour lists for sheep (data/sheep_colours.tres). The game only
## ever picks colours from here, never random ones. Open the file in the Godot
## Inspector to add, remove or tweak colours with colour pickers.

const PATH := "res://data/sheep_colours.tres"

static var _shared: SheepColours

@export var wools: Array[ColourRamp] = []
@export var skins: Array[ColourRamp] = []
@export var outfits: Array[OutfitSet] = []

static func load_default() -> SheepColours:
	return load(PATH)

## The colour lists the game uses, loaded once.
static func shared() -> SheepColours:
	if _shared == null:
		_shared = load_default()
	return _shared

func wool(wool_name: String) -> ColourRamp:
	return _find(wools, wool_name)

func skin(skin_name: String) -> ColourRamp:
	return _find(skins, skin_name)

func outfit(outfit_name: String) -> OutfitSet:
	for o in outfits:
		if o.name == outfit_name:
			return o
	return null

func wool_names() -> Array:
	return wools.map(func(r): return r.name)

## Combination rules (from the colour test): dark outfits never on dark wool,
## loud outfits only on light wool.
static func allowed(wool_ramp: ColourRamp, outfit_set: OutfitSet) -> bool:
	if outfit_set == null:
		return true
	if outfit_set.tag == "dark" and wool_ramp.tag == "dark":
		return false
	if outfit_set.tag == "loud" and wool_ramp.tag != "light":
		return false
	return true

func _find(list: Array, ramp_name: String) -> ColourRamp:
	for r in list:
		if r.name == ramp_name:
			return r
	return null
