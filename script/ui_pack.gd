class_name UIPack
extends RefCounted
## Reusable UI Pack helper for `res://assets/UI/UI_pack.png` and the Peaberry font family.
## Provides ready-to-use StyleBoxTexture panels, wide buttons, square icon TextureButtons,
## and font helpers for consistent styling across Sheep Hi Resort (excluding main_menu.tscn).

const TEXTURE_PATH := "res://assets/UI/UI_pack.png"
const BOARD_TEXTURE_PATH := "res://assets/UI/Ui.png"
const FONT_BASE_PATH := "res://fonts/Peaberry Base/PeaberryBase.ttf"
const FONT_MONO_PATH := "res://fonts/Peaberry Monospace/PeaberryMono.ttf"
const FONT_DOUBLE_PATH := "res://fonts/Peaberry Doublespace/PeaberryDoublespace.ttf"

# =============================================================================
# 1. 9-SLICE PANEL & FRAME REGIONS IN UI_pack.png (896x240)
# =============================================================================
const PANEL_REGIONS := {
	"cream_raised": Rect2(11, 11, 26, 28),
	"cream_flat": Rect2(59, 11, 26, 26),
	"cream_inset": Rect2(107, 11, 26, 26),
	"beige_raised": Rect2(11, 59, 26, 28),
	"beige_flat": Rect2(59, 59, 26, 26),
	"beige_inset": Rect2(107, 59, 26, 26),
	"tan_raised": Rect2(11, 107, 26, 28),
	"tan_flat": Rect2(59, 107, 26, 26),
	"tan_inset": Rect2(107, 107, 26, 26),
	"brown_raised": Rect2(11, 155, 26, 28),
	"brown_flat": Rect2(59, 155, 26, 26),
	"brown_inset": Rect2(107, 155, 26, 26),
	"wood_frame_light": Rect2(153, 9, 30, 30),
	"wood_frame_medium": Rect2(153, 57, 30, 30),
	"wood_frame_dark": Rect2(153, 105, 30, 30),
	"banner": Rect2(355, 178, 170, 60),
	"speech_bubble": Rect2(455, 139, 30, 28),
}

# =============================================================================
# 2. WIDE RECTANGULAR BUTTON REGIONS (90x27 normal / 90x25 pressed)
# =============================================================================
const WIDE_BTN_NORMAL := Rect2(163, 178, 90, 27)
const WIDE_BTN_PRESSED := Rect2(259, 180, 90, 25)
const PLAY_BTN_NORMAL := Rect2(163, 210, 90, 27)
const PLAY_BTN_PRESSED := Rect2(259, 212, 90, 25)
const COIN_REGION := Rect2(627, 98, 9, 12)
const STAR_REGION := Rect2(530, 97, 14, 13)
const WOOD_SIGN_REGION := Rect2(504, 131, 35, 41)
const SHOP_BOARD_REGION := Rect2(8, 167, 87, 81)

# Standalone small brown glyph icons in UI_pack.png (for placing inside wood_frame_light)
const STANDALONE_ICON_REGIONS := {
	"house": Rect2(822, 226, 14, 12),
	"star": Rect2(819, 195, 14, 12),
	"trophy": Rect2(852, 209, 14, 13),
	"crown": Rect2(869, 209, 14, 13),
	"chat": Rect2(802, 195, 14, 12),
	"dollar": Rect2(802, 209, 14, 13),
	"cart": Rect2(819, 209, 14, 13),
	"podium": Rect2(835, 209, 15, 13),
	"plus": Rect2(868, 226, 12, 12),
}

# =============================================================================
# 3. SQUARE ICON BUTTON REGIONS (22x24 normal / 22x22 pressed)
# =============================================================================
const ICON_BUTTON_REGIONS := {
	"blank": {
		"normal": Rect2(709, 36, 22, 24),
		"pressed": Rect2(741, 38, 22, 22),
	},
	"tick": {
		"normal": Rect2(837, 68, 22, 24),
		"pressed": Rect2(869, 70, 22, 22),
	},
	"cross": {
		"normal": Rect2(837, 100, 22, 24),
		"pressed": Rect2(869, 102, 22, 22),
	},
	"plus": {
		"normal": Rect2(837, 132, 22, 24),
		"pressed": Rect2(869, 134, 22, 22),
	},
	"minus": {
		"normal": Rect2(837, 164, 22, 24),
		"pressed": Rect2(869, 166, 22, 22),
	},
	"dollar": {
		"normal": Rect2(773, 132, 22, 24),
		"pressed": Rect2(805, 134, 22, 22),
	},
	"cart": {
		"normal": Rect2(773, 100, 22, 24),
		"pressed": Rect2(805, 102, 22, 22),
	},
	"home": {
		"normal": Rect2(773, 68, 22, 24),
		"pressed": Rect2(805, 70, 22, 22),
	},
	"settings": {
		"normal": Rect2(645, 68, 22, 24),
		"pressed": Rect2(677, 70, 22, 22),
	},
	"trophy": {
		"normal": Rect2(709, 68, 22, 24),
		"pressed": Rect2(741, 70, 22, 22),
	},
	"podium": {
		"normal": Rect2(773, 36, 22, 24),
		"pressed": Rect2(805, 38, 22, 22),
	},
	"star": {
		"normal": Rect2(837, 36, 22, 24),
		"pressed": Rect2(869, 38, 22, 22),
	},
	"crown": {
		"normal": Rect2(709, 100, 22, 24),
		"pressed": Rect2(741, 102, 22, 22),
	},
	"gamepad": {
		"normal": Rect2(645, 100, 22, 24),
		"pressed": Rect2(677, 102, 22, 22),
	},
	"chat": {
		"normal": Rect2(645, 132, 22, 24),
		"pressed": Rect2(677, 134, 22, 22),
	},
	"exclamation": {
		"normal": Rect2(709, 132, 22, 24),
		"pressed": Rect2(741, 134, 22, 22),
	},
	"skull": {
		"normal": Rect2(645, 164, 22, 24),
		"pressed": Rect2(677, 166, 22, 22),
	},
	"question": {
		"normal": Rect2(709, 164, 22, 24),
		"pressed": Rect2(741, 166, 22, 22),
	},
	"ban": {
		"normal": Rect2(772, 163, 22, 24),
		"pressed": Rect2(804, 165, 22, 22),
	},
}

# =============================================================================
# 4. REUSABLE FACTORY FUNCTIONS
# =============================================================================

static func get_texture() -> Texture2D:
	return load(TEXTURE_PATH) as Texture2D

static func get_font(variant: String = "base") -> FontFile:
	match variant:
		"mono":
			return load(FONT_MONO_PATH) as FontFile
		"double", "doublespace":
			return load(FONT_DOUBLE_PATH) as FontFile
		_:
			return load(FONT_BASE_PATH) as FontFile

## Creates a 9-slice StyleBoxTexture from UI_pack.png for panels and frames.
static func make_panel_style(
	variant: String = "beige_raised",
	content_margin: Vector4 = Vector4(12, 10, 12, 12),
	modulate: Color = Color.WHITE
) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = get_texture()
	style.region_rect = PANEL_REGIONS.get(variant, PANEL_REGIONS["beige_raised"])
	var border_m: float = 8.0 if variant.begins_with("wood_frame") else 7.0
	style.texture_margin_left = border_m
	style.texture_margin_top = border_m
	style.texture_margin_right = border_m
	style.texture_margin_bottom = border_m
	style.content_margin_left = content_margin.x
	style.content_margin_top = content_margin.y
	style.content_margin_right = content_margin.z
	style.content_margin_bottom = content_margin.w
	style.modulate_color = modulate
	return style

## Applies a 9-slice UI_pack.png panel style directly to a Panel or PanelContainer.
static func style_panel(
	panel: Control,
	variant: String = "beige_raised",
	content_margin: Vector4 = Vector4(12, 10, 12, 12),
	modulate: Color = Color.WHITE
) -> void:
	if not is_instance_valid(panel):
		return
	panel.add_theme_stylebox_override("panel", make_panel_style(variant, content_margin, modulate))

## Creates a 9-slice StyleBoxTexture for wide rectangular buttons from UI_pack.png.
static func make_wide_button_style(pressed: bool = false, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = get_texture()
	style.region_rect = WIDE_BTN_PRESSED if pressed else WIDE_BTN_NORMAL
	style.texture_margin_left = 6.0
	style.texture_margin_top = 6.0
	style.texture_margin_right = 6.0
	style.texture_margin_bottom = 6.0 if pressed else 7.0
	style.content_margin_left = 10.0
	style.content_margin_top = 7.0 if pressed else 5.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 5.0 if pressed else 7.0
	style.modulate_color = modulate
	return style

## Styles a standard Godot Button using UI_pack.png wide button regions and optional tint.
static func style_button(
	btn: Button,
	tint: Color = Color.WHITE,
	font_color: Color = Color(0.22, 0.12, 0.06, 1.0)
) -> void:
	if not is_instance_valid(btn):
		return
	var norm := make_wide_button_style(false, tint)
	var hov := make_wide_button_style(false, Color(tint.r * 1.08, tint.g * 1.06, tint.b * 0.98, tint.a))
	var prs := make_wide_button_style(true, Color(tint.r * 0.92, tint.g * 0.90, tint.b * 0.88, tint.a))
	var dis := make_wide_button_style(true, Color(0.7, 0.68, 0.65, 0.7))
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", prs)
	btn.add_theme_stylebox_override("disabled", dis)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color.darkened(0.15))
	btn.add_theme_color_override("font_pressed_color", font_color.darkened(0.2))
	btn.add_theme_color_override("font_focus_color", font_color)

## Returns an AtlasTexture for one of the square icon buttons in UI_pack.png.
## Valid icon_name values: "tick", "cross", "plus", "minus", "dollar", "cart",
## "home", "settings", "trophy", "podium", "star", "crown", "gamepad", "chat",
## "exclamation", "skull", "question", "ban", "blank".
static func make_icon_atlas(icon_name: String, pressed: bool = false) -> AtlasTexture:
	var pair: Dictionary = ICON_BUTTON_REGIONS.get(icon_name, ICON_BUTTON_REGIONS["blank"])
	var atlas := AtlasTexture.new()
	atlas.atlas = get_texture()
	atlas.region = pair["pressed"] if pressed else pair["normal"]
	return atlas

static func make_region_atlas(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = get_texture()
	atlas.region = region
	return atlas

static func make_shop_board_atlas() -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(BOARD_TEXTURE_PATH) as Texture2D
	atlas.region = SHOP_BOARD_REGION
	return atlas

static func make_standalone_icon_atlas(icon_key: String = "house") -> AtlasTexture:
	var reg: Rect2 = STANDALONE_ICON_REGIONS.get(icon_key, STANDALONE_ICON_REGIONS["house"])
	return make_region_atlas(reg)

## Creates a ready-to-use TextureButton with normal & pressed states from UI_pack.png.
static func make_icon_button(
	icon_name: String,
	min_size: Vector2 = Vector2(28, 28),
	tooltip: String = "",
	btn_name: String = ""
) -> TextureButton:
	var btn := TextureButton.new()
	if not btn_name.is_empty():
		btn.name = btn_name
	var norm := make_icon_atlas(icon_name, false)
	var prs := make_icon_atlas(icon_name, true)
	btn.texture_normal = norm
	btn.texture_pressed = prs
	btn.texture_hover = norm
	btn.custom_minimum_size = min_size
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.tooltip_text = tooltip
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return btn

