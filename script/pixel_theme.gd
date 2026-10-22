class_name PixelTheme
extends RefCounted
## One look for every window, button and label: a pixel font, one palette, and a
## chunky bevelled frame generated pixel-by-pixel (so it stays crisp at any
## integer scale). Swap the frame for an artist's 9-slice PNG later by changing
## frame() only.

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const FONT_BOLD := preload("res://assets/fonts/PixelOperator8-Bold.ttf")
const SIZE := 8           # PixelOperator8 is drawn on an 8px grid; use 8 or 16 only
const SIZE_BIG := 16

# Palette (taken from the mockups)
const INK := Color("1c120c")          # outlines
const TEXT := Color("2a1c12")         # dark text on paper
const TEXT_LIGHT := Color("fff4dc")   # light text on wood / screens
const TEXT_MUTED := Color("7a6450")
const WOOD_DARK := Color("4a2c16")
const WOOD := Color("7a4a24")
const PAPER := Color("f4ead2")
const PAPER_BLUE := Color("dcebf7")   # ID card
const PAPER_GREEN := Color("e2f2d8")  # health certificate
const PAPER_YELLOW := Color("fbefc8") # booking voucher
const PAPER_PINK := Color("f7ddd2")   # rulebook
const SCREEN := Color("bfe6f5")
const SCREEN_DARK := Color("1f3f52")
const GOLD := Color("f2c14e")
const GREEN := Color("4f9a3e")
const RED := Color("b8473a")
const BLUE := Color("6fa8dc")
const PURPLE := Color("9a7ad0")
const HIGHLIGHT := Color("ffc23a")    # selected field when comparing

static var _cache := {}

## An 11x11 chunky frame, 9-sliced with 4px margins. From the outside in:
## 1px ink outline (corners cut), 1px dark rim, 1px bevel (light top-left,
## dark bottom-right), then the fill.
static func frame(fill: Color, padding := 6) -> StyleBoxTexture:
	var key := fill.to_html()
	var tex: ImageTexture = _cache.get(key)
	if tex == null:
		const N := 11
		var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
		var rim := fill.darkened(0.45)
		var light := fill.lightened(0.4)
		var dark := fill.darkened(0.2)
		for y in N:
			for x in N:
				var ring := mini(mini(x, y), mini(N - 1 - x, N - 1 - y))  # 0 = outermost
				var corner := (x == 0 or x == N - 1) and (y == 0 or y == N - 1)
				var c := fill
				if corner:
					c = Color(0, 0, 0, 0)
				elif ring == 0:
					c = INK
				elif ring == 1:
					c = rim
				elif ring == 2:
					c = light if (x == 2 or y == 2) else dark
				img.set_pixel(x, y, c)
		tex = ImageTexture.create_from_image(img)
		_cache[key] = tex
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 4
	sb.texture_margin_top = 4
	sb.texture_margin_right = 4
	sb.texture_margin_bottom = 4
	sb.set_content_margin_all(padding)
	return sb

static func flat(color: Color, padding := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.anti_aliasing = false
	sb.set_content_margin_all(padding)
	return sb

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = SIZE

	for type in ["PanelContainer", "Panel"]:
		t.set_stylebox("panel", type, frame(PAPER))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", FONT_BOLD)
	t.set_constant("line_separation", "Label", 2)
	t.set_constant("line_separation", "RichTextLabel", 2)

	t.set_stylebox("normal", "LineEdit", frame(Color.WHITE, 3))
	t.set_stylebox("focus", "LineEdit", flat(Color(0, 0, 0, 0)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("caret_color", "LineEdit", TEXT)

	t.set_stylebox("panel", "ItemList", frame(Color.WHITE, 3))
	t.set_stylebox("focus", "ItemList", flat(Color(0, 0, 0, 0)))
	t.set_stylebox("selected", "ItemList", flat(GOLD, 1))
	t.set_stylebox("selected_focus", "ItemList", flat(GOLD, 1))
	t.set_stylebox("hovered", "ItemList", flat(SCREEN, 1))
	t.set_stylebox("cursor", "ItemList", flat(Color(0, 0, 0, 0)))
	t.set_stylebox("cursor_unfocused", "ItemList", flat(Color(0, 0, 0, 0)))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", TEXT)
	t.set_color("font_hovered_color", "ItemList", TEXT)
	t.set_constant("v_separation", "ItemList", 2)

	t.set_stylebox("scroll", "VScrollBar", flat(PAPER.darkened(0.15), 0))
	t.set_stylebox("grabber", "VScrollBar", flat(WOOD, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(WOOD.lightened(0.2), 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(WOOD_DARK, 2))

	t.set_stylebox("panel", "TooltipPanel", frame(PAPER, 3))
	t.set_color("font_color", "TooltipLabel", TEXT)

	_button_styles(t, "Button", PAPER)
	return t

static func _button_styles(t: Theme, type: String, fill: Color) -> void:
	t.set_stylebox("normal", type, frame(fill, 4))
	t.set_stylebox("hover", type, frame(fill.lightened(0.15), 4))
	t.set_stylebox("pressed", type, frame(fill.darkened(0.2), 4))
	t.set_stylebox("disabled", type, frame(fill.darkened(0.45), 4))
	t.set_stylebox("focus", type, flat(Color(0, 0, 0, 0)))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, type, TEXT)
	t.set_color("font_disabled_color", type, TEXT.lightened(0.25))

## Recolour one button while keeping the shared frame shape.
static func tint_button(b: Button, fill: Color) -> void:
	b.add_theme_stylebox_override("normal", frame(fill, 4))
	b.add_theme_stylebox_override("hover", frame(fill.lightened(0.15), 4))
	b.add_theme_stylebox_override("pressed", frame(fill.darkened(0.2), 4))
	b.add_theme_stylebox_override("disabled", frame(fill.darkened(0.45), 4))
