@tool
class_name OutfitSet
extends Resource
## A group of clothing colours chosen to go together: top (shirt, jacket),
## accent (vest, trim, second colour) and bottom (trousers, skirt). Hats use the
## top colour.

@export var name := ""
## calm: goes with any wool. loud: only on light wool. dark: never on dark wool.
@export_enum("calm", "loud", "dark") var tag := "calm"
@export var top: ColourRamp
@export var accent: ColourRamp
@export var bottom: ColourRamp
