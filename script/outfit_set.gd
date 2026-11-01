@tool
class_name OutfitSet
extends Resource
## A group of clothing colours chosen to go together: top (shirts, jackets,
## vests), accent (hats) and bottom (trousers, skirts).

@export var name := ""
## calm: goes with any wool. loud: only on light wool. dark: never on dark wool.
@export_enum("calm", "loud", "dark") var tag := "calm"
@export var top: ColourRamp
@export var accent: ColourRamp
@export var bottom: ColourRamp
