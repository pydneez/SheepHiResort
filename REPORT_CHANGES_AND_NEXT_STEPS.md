# Resort Progression, Peaberry Font & UI Pack Integration Report

## 1. Summary of Changes Made

### A. Day 1 Starting Layout & Quarter-Based Land Expansion
- **Limited Starting Land (1/4 of Map)**:
  - The full resort grid is `32x24` cells (`768` total `32x32` cells = `64x48` `16x16` grass subtiles).
  - Day 1 begins with **Quarter 1 (Center Starting Plot)** unlocked: `x in [-8..7], y in [-6..5]` (`16x12 = 192` cells, exact **25%** of the total map).
  - In [`script/phase2_resort.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/phase2_resort.gd) (`rebuild_grass_tilemap()`), the Grass `TileMapLayer` dynamically rebuilds its autotiled grass island from `GameManager.resort_layout["land_cells"]` using `Terrain Set 1 / Terrain 0 ("Grass")`.
- **Starting Cross Pathway & 4 Day-1 Facilities**:
  - Configured in [`script/game_manager.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/game_manager.gd) (`DEFAULT_FACILITY_INSTANCES` and `_make_default_cross_pathways()`) and [`scene/phase2_resort.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/phase2_resort.tscn):
    - **Cross Pathway**: Horizontal arm (`x in [-5..5], y = 0`) and vertical arm (`x = 0, y in [-3..3]`).
    - **Main Building** (`building_row = 8`, `position = Vector2(16, 172)`): Placed at the **bottom** end of the cross pathway; acts as the guest spawn point in Phase 2 (`base_payout = 0`).
    - **Cabin** (`building_row = 0`, `position = Vector2(16, -78)`): Placed at the **top** end of the cross pathway.
    - **Restaurant** (`building_row = 7`, `position = Vector2(-156, 0)`): Placed at the **left** end of the cross pathway.
    - **Jail** (`building_row = 11`, `position = Vector2(188, 0)`): Placed at the **right** end of the cross pathway.
- **Quarter-Based Land Purchases with Increasing Prices**:
  - Defined 4 equal 192-cell quarters in [`script/game_manager.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/game_manager.gd):
    1. **Quarter 1 (Center Start)**: Owned on Day 1 (`$0`)
    2. **Quarter 2 (West Wing)**: `x in [-16..-9], y in [-11..12]` (`192` cells)
    3. **Quarter 3 (East Wing)**: `x in [8..15], y in [-11..12]` (`192` cells)
    4. **Quarter 4 (North & South Meadows)**: `x in [-8..7], y in [-11..-7] U [6..12]` (`192` cells)
  - **Increasing Price Schedule (`QUARTER_PRICES`)**:
    - **2nd Quarter Purchase**: **`$100`** (expands resort from 25% to 50%)
    - **3rd Quarter Purchase**: **`$200`** (expands resort from 50% to 75%)
    - **4th Quarter Purchase**: **`$300`** (expands resort from 75% to 100%)
  - In [`script/resort_layout_editor.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/resort_layout_editor.gd), players can unlock quarters either via the **Buy Quarter** buttons in the Left Panel (`$ Buy Quarter #2 ($100)`, `Q2 West`, `Q3 East`, `Q4 N/S`) or by selecting **Map Select** (`BUY_LAND`) and clicking any locked quarter directly on the map (which highlights the entire quarter on hover).

---

### B. Peaberry Font Family Everywhere (Excluding `main_menu.tscn`)
- Updated [`project.godot`](file:///d:/Coding/game%20dev/SheepHiResort/project.godot) (`gui/theme/custom_font`) and [`ui/game_theme.tres`](file:///d:/Coding/game%20dev/SheepHiResort/ui/game_theme.tres) to use:
  - [`fonts/Peaberry Base/PeaberryBase.ttf`](file:///d:/Coding/game%20dev/SheepHiResort/fonts/Peaberry%20Base/PeaberryBase.ttf) for `default_font` and `RichTextLabel` normal/bold/italics fonts.
  - [`fonts/Peaberry Monospace/PeaberryMono.ttf`](file:///d:/Coding/game%20dev/SheepHiResort/fonts/Peaberry%20Monospace/PeaberryMono.ttf) for `RichTextLabel/fonts/mono_font`.
- [`scene/main_menu.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/main_menu.tscn) remains completely untouched and isolated with its own `Theme_menu` resource.

---

### C. Reusable `UI_pack.png` System & Scene Restyling (Excluding `main_menu.tscn`)
- **Reusable Helper Class ([`script/ui_pack.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/ui_pack.gd) — `class_name UIPack`)**:
  - Centralizes all pixel-exact 9-slice panel regions (`cream_raised`, `beige_raised`, `beige_inset`, `tan_raised`, `brown_raised`, `wood_frame_light`, `wood_frame_medium`, `wood_frame_dark`, `banner`, `speech_bubble`), wide button regions (`WIDE_BTN_NORMAL`, `WIDE_BTN_PRESSED`), and all 19 square icon button pairs (`tick`, `cross`, `plus`, `minus`, `dollar`, `cart`, `home`, `settings`, `trophy`, `podium`, `star`, `crown`, `gamepad`, `chat`, `exclamation`, `skull`, `question`, `ban`) from [`assets/UI/UI_pack.png`](file:///d:/Coding/game%20dev/SheepHiResort/assets/UI/UI_pack.png).
  - Provides one-line static helpers for future UI work:
    - `UIPack.make_panel_style(variant, content_margin, modulate)` / `UIPack.style_panel(panel, variant, ...)`
    - `UIPack.make_wide_button_style(pressed, modulate)` / `UIPack.style_button(button, tint, font_color)`
    - `UIPack.make_icon_atlas(icon_name, pressed)` / `UIPack.make_icon_button(icon_name, min_size, tooltip)`
    - `UIPack.get_font(variant)` (`"base"`, `"mono"`, `"doublespace"`)
- **Reusable Scene Prefab ([`scene/ui_pack_panel.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/ui_pack_panel.tscn) & [`script/ui_pack_panel.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/ui_pack_panel.gd) — `class_name UIPackPanel`)**:
  - Can be instanced in any scene and configured via Inspector dropdown (`panel_variant`, `content_margins`, `panel_tint`).
- **Global Theme & Scene Updates**:
  - Updated [`ui/game_theme.tres`](file:///d:/Coding/game%20dev/SheepHiResort/ui/game_theme.tres) so default `Button`, `Panel`, `PanelContainer`, `PopupPanel`, `LineEdit`, `ItemList`, and `TooltipPanel` controls automatically render using `UI_pack.png` 9-slice textures.
  - Updated [`scene/front_desk.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/front_desk.tscn), [`scene/computer_window.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/computer_window.tscn), [`scene/day_popup.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/day_popup.tscn), [`scene/speech_bubble.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/speech_bubble.tscn), [`scene/desk_document.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/desk_document.tscn), [`scene/week_summary.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/week_summary.tscn), [`scene/phase2_resort.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/phase2_resort.tscn), and [`script/resort_layout_editor.gd`](file:///d:/Coding/game%20dev/SheepHiResort/script/resort_layout_editor.gd) to use `UI_pack.png` frames, panels, wide buttons, and square icon buttons (`+`, `-`, `$`, `✓`, `✖`).

---

## 2. Potential Problems & Things to Watch Out For

1. **Peaberry Font Glyph Width & Line Spacing**:
   - `PeaberryBase.ttf` has slightly wider glyphs and taller ascenders/descenders than the previous `pixelFont-7-8x14-sproutLands.ttf`.
   - We adjusted `default_font_size` in [`ui/game_theme.tres`](file:///d:/Coding/game%20dev/SheepHiResort/ui/game_theme.tres) from `20` to `18` and widened key buttons (`TabDbButton`, `TabLayoutButton`, `TopNavBar`, `LeftPanel`) to prevent text clipping.
   - **Where to check**: Long procedural guest names or long region names on `DeskDocument` cards (`ID Card`, `Booking Voucher`) and `WeekSummary` stats may wrap or sit close to the right margin at `18px`.
2. **Decorative Trees/Fences Outside Starting Quarter**:
   - In [`scene/phase2_resort.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/phase2_resort.tscn), only the `Grass` layer is dynamically rebuilt per unlocked quarter; if static decorative props are placed on the `Decor` `TileMapLayer` in outer quarters (`Q2–Q4`), they would remain visible over empty space before those quarters are bought. Currently `Decor` is minimal, but if you paint trees/fences in the editor, they should either be placed inside Quarter 1 or filtered by `GameManager.is_land_cell_unlocked(cell)`.
3. **Facility Shop Availability on Day 1**:
   - On Day 1, the resort starts with only `Main Building`, `Cabin`, `Restaurant`, and `Jail` on the map. However, `Wool Salon` is still listed in the Facility Shop in the Layout Editor for `$50`. If you want `Wool Salon` to be locked until a specific day (e.g., Day 2 or Day 3 when Merino/Shetland wool checks or higher guest counts appear), we can gate shop cards by `GameManager.current_day`.

---

## 3. Suggested Next Steps

1. **Fine-Tune Peaberry Font Sizes Per Screen**:
   - Play through a Day 1 shift and inspect `DeskDocument` papers, `DayPopup` briefings, and `WeekSummary`. If any header feels too tight, we can switch specific headers to `PeaberryDoublespace.ttf` or adjust `line_spacing` in `ui/game_theme.tres`.
2. **Persist Unlocked Quarters & Layout Across Save/Load**:
   - Wire the `LoadButton` on [`scene/main_menu.tscn`](file:///d:/Coding/game%20dev/SheepHiResort/scene/main_menu.tscn) to save/load `GameManager.resort_layout` (which already stores `land_cells`, `pathways`, and `facility_instances`) to `user://savegame.json`.
3. **Progressive Facility Unlocking by Day**:
   - Unlock new facility types (such as `Wool Salon` on Day 2/3 or additional decorative buildings from `Buildings1.png`) as the player progresses through the week or unlocks more land quarters.
4. **Visual Boundary Fence / Locked Quarter Signposts**:
   - Draw wooden fences or "FOR SALE: $100 / $200 / $300" signposts on locked quarters (`Q2`, `Q3`, `Q4`) during Phase 2 so players can visually see expansion areas even during Rush Hour.

