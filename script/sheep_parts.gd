class_name SheepParts
extends RefCounted
## Catalogue of the sheep part pictures (the paper-doll sheep). Scans the folders
## when created, so adding a new hat is just dropping hat_07.png into
## assets/sheep_parts/hat/ — no code to change.
##
## File names (all on the same 336x432 canvas, full canvas, never cropped):
##   base/base_wool_01.png  base/base_skin_01.png  base/base_detail_01.png   one base sheep (a trio)
##   base/base_skin_wolf_01.png, base/base_detail_wolf_01.png               wolf versions of a base layer
##   <slot>/<slot>_03.png            a normal part (e.g. eyes/eyes_03.png)
##   <slot>/<slot>_03_detail.png     fixed-colour bits drawn on top of part 03 (e.g. stars on a hat)
##   <slot>/<slot>_07_fixed.png      a special part kept in its real colours, never recoloured
##   <slot>/<slot>_wolf_01.png       a wolf giveaway for that slot (always real colours)

const ROOT := "res://assets/sheep_parts"
## Used while the real folder has no base sheep yet (programmer art).
const PLACEHOLDER_ROOT := "res://assets/sheep_parts_placeholder"
const CANVAS := Vector2i(336, 432)
## The head, cropped for the ID-card photo.
const HEAD_AREA := Rect2(72, 24, 192, 168)
## Back to front. "base" is the wool + skin + detail trio.
const LAYER_ORDER := ["back", "base", "bottom", "top", "ears", "eyes", "mouth", "headwool", "hat", "front"]
## Every sheep has these; the other slots are optional.
const REQUIRED := ["eyes", "mouth", "headwool"]
## Slots painted in the 4 greys, and which colour recolours them: wool, skin, or
## the outfit set's top / accent / bottom. Wolf parts, _fixed parts and _detail
## files are never recoloured.
const RECOLOUR := {"bottom": "bottom", "top": "top", "hat": "accent", "ears": "skin", "headwool": "wool"}

var root := ""
## "01" -> {wool, skin, detail} file paths, plus wolf_skin / wolf_detail when drawn.
var bases := {}
## slot -> Array of {id, path, detail, fixed, wolf}
var parts := {}
## Files or folders that break the naming rules (shown by tests/test_sheep_parts.gd).
var problems: Array[String] = []

static var _shared: SheepParts

## The catalogue the game uses, scanned once.
static func shared() -> SheepParts:
	if _shared == null:
		_shared = load_default()
	return _shared

static func load_default() -> SheepParts:
	var real := SheepParts.new(ROOT)
	if not real.bases.is_empty():
		return real
	return SheepParts.new(PLACEHOLDER_ROOT)

func _init(dir := ROOT) -> void:
	root = dir
	_scan()

## One part by its id (e.g. "hat_02"), or {} if there is no such part.
func part(slot: String, id: String) -> Dictionary:
	for p in parts.get(slot, []):
		if p.id == id:
			return p
	return {}

## Parts available for a slot. wolf = true gives the wolf giveaways instead.
func options(slot: String, wolf := false) -> Array:
	return parts.get(slot, []).filter(func(p): return p.wolf == wolf)

## Every picture file with whether the game recolours it (used by the checks).
func all_files() -> Array:
	var out := []
	for n in bases:
		var b: Dictionary = bases[n]
		out.append({"path": b.wool, "recolour": true})
		out.append({"path": b.skin, "recolour": true})
		out.append({"path": b.detail, "recolour": false})
		for k in ["wolf_skin", "wolf_detail"]:
			if b.has(k):
				out.append({"path": b[k], "recolour": false})
	for slot in parts:
		for p in parts[slot]:
			out.append({"path": p.path, "recolour": recolours(slot, p)})
			if p.detail != "":
				out.append({"path": p.detail, "recolour": false})
	return out

## Is this part painted in greys and recoloured by the game?
static func recolours(slot: String, part: Dictionary) -> bool:
	return RECOLOUR.has(slot) and not part.wolf and not part.fixed

func _scan() -> void:
	if not DirAccess.dir_exists_absolute(root):
		return
	for entry in ResourceLoader.list_directory(root):
		if not entry.ends_with("/"):
			continue
		var slot: String = entry.trim_suffix("/")
		if slot == "base":
			_scan_bases()
		elif slot in LAYER_ORDER:
			_scan_slot(slot)
		else:
			problems.append("%s/%s: unknown folder (expected one of %s)" % [root, slot, ", ".join(LAYER_ORDER)])

func _scan_bases() -> void:
	var dir := root + "/base"
	var found := {}   # "01" -> {wool: path, ...}
	var re := RegEx.create_from_string("^base_(wool|skin|detail)(_wolf)?_(\\d{2})\\.png$")
	for file in _files(dir):
		var m := re.search(file)
		if m == null:
			problems.append("%s/%s: name should look like base_wool_01.png, base_skin_01.png, base_detail_01.png" % [dir, file])
			continue
		var key: String = ("wolf_" if m.get_string(2) != "" else "") + m.get_string(1)
		if key == "wolf_wool":
			problems.append("%s/%s: wolves have no separate wool; draw base_skin_wolf / base_detail_wolf instead" % [dir, file])
			continue
		var n := m.get_string(3)
		if not found.has(n):
			found[n] = {}
		found[n][key] = dir + "/" + file
	for n in found:
		var b: Dictionary = found[n]
		var missing := ["wool", "skin", "detail"].filter(func(k): return not b.has(k))
		if missing.is_empty():
			bases[n] = b
		else:
			problems.append("%s: base %s is missing %s" % [dir, n, ", ".join(missing.map(func(k): return "base_%s_%s.png" % [k, n]))])

func _scan_slot(slot: String) -> void:
	var dir := root + "/" + slot
	var re := RegEx.create_from_string("^%s(_wolf)?_(\\d{2})(_detail|_fixed)?\\.png$" % slot)
	var by_id := {}
	var details := {}
	for file in _files(dir):
		var m := re.search(file)
		if m == null:
			problems.append("%s/%s: name should look like %s_01.png (or %s_01_detail.png, %s_01_fixed.png, %s_wolf_01.png)" % [dir, file, slot, slot, slot, slot])
			continue
		var id := "%s%s_%s" % [slot, m.get_string(1), m.get_string(2)]
		if m.get_string(3) == "_detail":
			details[id] = dir + "/" + file
		else:
			by_id[id] = {"id": id, "path": dir + "/" + file, "detail": "",
				"fixed": m.get_string(3) == "_fixed", "wolf": m.get_string(1) != ""}
	for id in details:
		if by_id.has(id):
			by_id[id].detail = details[id]
		else:
			problems.append("%s: %s has no matching %s.png" % [dir, details[id].get_file(), id])
	var list := by_id.values()
	list.sort_custom(func(a, b): return a.id < b.id)
	parts[slot] = list

func _files(dir: String) -> Array:
	return Array(ResourceLoader.list_directory(dir)).filter(func(f): return not f.ends_with("/"))
