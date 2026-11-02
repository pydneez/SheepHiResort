class_name SheepCharacters
extends RefCounted
## Catalogue of the drawn sheep: every data/sheep_characters/<id>.tres. Adding
## a sheep is adding a file there — no code to change.

const ROOT := "res://data/sheep_characters"
const PIXEL_ROOT := "res://assets/sheep_character_pixel"

## id -> SheepCharacter
var all := {}
## Ids of the sheep the generator may pick: they have a normal face and a
## pixel sprite (so they can carry on into Phase 2).
var playable: Array[String] = []

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
	playable.sort()

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
