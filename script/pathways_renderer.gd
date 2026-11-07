class_name PathwaysRenderer
extends Node2D
## Renders player-constructed pathways in the Phase 2 Resort world.
## Positioned at z_index = -3 so it renders smoothly between the base grass tilemap and entities.

const CELL_SIZE: float = 32.0

# Terrain configuration using the "Pathway" terrain in resort_tileset_ground.tres
# (Terrain Set 0 -> Terrain 0: "Pathway")
const TILESET_PATH := "res://resource/resort_tileset_ground.tres"
const TERRAIN_SET_ID: int = 0
const TERRAIN_ID: int = 0
const SUBTILES_PER_CELL: int = 2

# Fallback single-tile configuration (used only if terrain autotile is disabled)
const TILE_MAP_PATH := "res://assets/PhaseII_Map/Tile Map.png"
const CUSTOM_TILE_REGION := Rect2(64, 592, 32, 32)

@export var use_terrain_autotile: bool = true

var tile_map_tex: Texture2D = null
var path_tilemap_layer: TileMapLayer = null

func _ready() -> void:
	z_index = -3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(TILE_MAP_PATH):
		tile_map_tex = load(TILE_MAP_PATH)
	_ensure_tilemap_layer()
	refresh()

func _ensure_tilemap_layer() -> void:
	if path_tilemap_layer and is_instance_valid(path_tilemap_layer):
		return
	path_tilemap_layer = TileMapLayer.new()
	path_tilemap_layer.name = "PathTileMapLayer"
	path_tilemap_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if ResourceLoader.exists(TILESET_PATH):
		path_tilemap_layer.tile_set = load(TILESET_PATH)
	add_child(path_tilemap_layer)

func refresh() -> void:
	_ensure_tilemap_layer()
	_rebuild_terrain_layer()
	queue_redraw()

func _rebuild_terrain_layer() -> void:
	if not path_tilemap_layer or not is_instance_valid(path_tilemap_layer):
		return
	path_tilemap_layer.clear()
	if not use_terrain_autotile or path_tilemap_layer.tile_set == null:
		path_tilemap_layer.visible = false
		return

	path_tilemap_layer.visible = true
	var paths: Array = GameManager.resort_layout.get("pathways", [])
	if paths.is_empty():
		return

	# Each 32x32 pathway cell maps to a 2x2 cluster of 16x16 tiles
	var terrain_cells: Array[Vector2i] = []
	for cell in paths:
		if not cell is Vector2i:
			continue
		if SUBTILES_PER_CELL == 2:
			var bx: int = cell.x * 2
			var by: int = cell.y * 2
			terrain_cells.append(Vector2i(bx, by))
			terrain_cells.append(Vector2i(bx + 1, by))
			terrain_cells.append(Vector2i(bx, by + 1))
			terrain_cells.append(Vector2i(bx + 1, by + 1))
		else:
			terrain_cells.append(cell)

	if not terrain_cells.is_empty():
		path_tilemap_layer.set_cells_terrain_connect(terrain_cells, TERRAIN_SET_ID, TERRAIN_ID, false)

func _draw() -> void:
	# Active autotiling is rendered by PathTileMapLayer
	if use_terrain_autotile and path_tilemap_layer and path_tilemap_layer.tile_set != null:
		return

	var paths: Array = GameManager.resort_layout.get("pathways", [])
	if paths.is_empty():
		return

	if tile_map_tex:
		for cell in paths:
			if not cell is Vector2i:
				continue
			var base := Vector2(cell.x * CELL_SIZE, cell.y * CELL_SIZE)
			var dest_rect := Rect2(base, Vector2(CELL_SIZE, CELL_SIZE))
			draw_texture_rect_region(tile_map_tex, dest_rect, CUSTOM_TILE_REGION)
