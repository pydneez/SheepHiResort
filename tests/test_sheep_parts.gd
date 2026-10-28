extends "res://tests/game_test.gd"
## Checks the sheep part pictures and the colour lists, so a wrongly named or
## sized file shows up as a red check on the pull request with the file's name.

## Grey files may contain neutral greys and dark outlines; a few coloured
## pixels from soft edges are fine, more than this share is not.
const MAX_COLOURED_SHARE := 0.01

func _initialize() -> void:
	print("test_sheep_parts")
	for root in [SheepParts.ROOT, SheepParts.PLACEHOLDER_ROOT]:
		if not DirAccess.dir_exists_absolute(root):
			print("  (no %s folder yet)" % root)
			continue
		_check_folder(SheepParts.new(root))
	_check_colours(SheepColours.load_default())
	finish()

func _check_folder(cat: SheepParts) -> void:
	print("%s" % cat.root)
	for p in cat.problems:
		check(false, p)
	if cat.problems.is_empty():
		check(true, "all file and folder names follow the rules")
	if cat.bases.is_empty():
		print("  (no complete base sheep yet)")
	else:
		for slot in SheepParts.REQUIRED:
			check(not cat.options(slot).is_empty(), "has at least one %s part" % slot)
	# Size and colour are checked for every picture, even before the set is complete.
	var wrong_size := []
	var too_colourful := []
	for f in cat.all_files():
		var img := Image.load_from_file(ProjectSettings.globalize_path(f.path))
		if img.get_size() != SheepParts.CANVAS:
			wrong_size.append("%s is %dx%d" % [f.path.get_file(), img.get_width(), img.get_height()])
		elif f.recolour:
			var share := _coloured_share(img)
			if share > MAX_COLOURED_SHARE:
				too_colourful.append("%s (%.0f%% coloured pixels)" % [f.path.get_file(), share * 100.0])
	check(wrong_size.is_empty(), "every picture is %dx%d (full canvas, not cropped) %s"
		% [SheepParts.CANVAS.x, SheepParts.CANVAS.y, "" if wrong_size.is_empty() else str(wrong_size)])
	check(too_colourful.is_empty(), "recoloured parts are painted in greys %s"
		% ("" if too_colourful.is_empty() else str(too_colourful)))

## Share of visible pixels that have colour in them (not grey, not dark outline).
func _coloured_share(img: Image) -> float:
	img.convert(Image.FORMAT_RGBA8)
	var visible := 0
	var coloured := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			visible += 1
			var spread := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			if spread > 0.08 and c.get_luminance() > 0.2:
				coloured += 1
	return float(coloured) / maxi(visible, 1)

func _check_colours(c: SheepColours) -> void:
	print(SheepColours.PATH)
	check(c != null, "the colour lists load")
	if c == null:
		return
	check(not c.wools.is_empty() and not c.skins.is_empty() and not c.outfits.is_empty(),
		"there are wool, skin and outfit colours (%d / %d / %d)" % [c.wools.size(), c.skins.size(), c.outfits.size()])
	for list in [c.wools, c.skins]:
		var names: Array = list.map(func(r): return r.name)
		check(names.size() == _unique(names).size(), "names are unique: %s" % ", ".join(names))
	var incomplete := c.outfits.filter(func(o): return o.top == null or o.accent == null or o.bottom == null)
	check(incomplete.is_empty(), "every outfit set has top, accent and bottom colours")
	# The generator must always find an outfit that suits the wool.
	for w in c.wools:
		var fits := c.outfits.filter(func(o): return SheepColours.allowed(w, o))
		check(not fits.is_empty(), "%s wool has outfits that suit it (%d)" % [w.name, fits.size()])
		var faces := c.skins.filter(func(s): return SheepColours.skin_allowed(w, s))
		check(not faces.is_empty(), "%s wool has skins that suit it (%d)" % [w.name, faces.size()])

func _unique(a: Array) -> Array:
	var seen := {}
	for v in a:
		seen[v] = true
	return seen.keys()
