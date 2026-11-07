class_name SheepCharacters
extends RefCounted
## Catalogue of the drawn sheep: every data/sheep_characters/<id>.tres. Adding
## a sheep is adding a file there — no code to change.

const ROOT := "res://data/sheep_characters"
const PIXEL_ROOT := "res://assets/sheep_character_pixel"
const RARE_IDS := ["imposter_sheep", "influ_sheep"]

## id -> SheepCharacter
var all := {}
## Ids of all playable sheep the generator may pick (includes normal and rare).
var playable: Array[String] = []
## Ids of the normal sheep the generator picks from (includes epic_sheep).
var normal_playable: Array[String] = []
## Ids of rare special guests (1 in 20 chance: imposter_sheep, influ_sheep).
var rare_playable: Array[String] = []

static var _shared: SheepCharacters

## The catalogue the game uses, loaded once.
static func shared() -> SheepCharacters:
	if _shared == null:
		_shared = SheepCharacters.new()
	return _shared

func _init(dir := ROOT) -> void:
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".tres"):
			continue
		var c := load(dir.path_join(file)) as SheepCharacter
		if c == null:
			push_warning("SheepCharacters: %s is not a SheepCharacter" % file)
			continue
		all[c.id] = c
		if c.body != null and c.pixel != null and not c.normal_faces().is_empty():
			playable.append(c.id)
			if c.id in RARE_IDS:
				rare_playable.append(c.id)
			else:
				normal_playable.append(c.id)
	playable.sort()
	normal_playable.sort()
	rare_playable.sort()

func get_character(id: String) -> SheepCharacter:
	return all.get(id)

## A guest's sprite in Phase 2: the pixel version of the sheep they were at the
## front desk (appearance.look.character). A guest without one (made by hand)
## gets a sheep picked by name.
func pixel_for(guest: Dictionary) -> Texture2D:
	var look: Dictionary = guest.get("appearance", {}).get("look", {})
	var c := get_character(look.get("character", ""))
	if c == null or c.pixel == null:
		if playable.is_empty():
			return null
		var guest_name: String = guest.get("truth", {}).get("name", "Sheep")
		c = get_character(playable[absi(guest_name.hash()) % playable.size()])
	return c.pixel
