#tower_preview.gd
extends Node2D
class_name TowerPreview

#get a reference to the child sprite2d node
var tower_sprite: Sprite2D
var tower_type: Towers.Type

#define tint colors
const VALID_TINT = Color(1, 1, 1, 0.7)
const INVALID_TINT = Color(1, 0.3, 0.3, 0.7)
const BASE_PREVIEW_SCALE = 0.06

func _ready() -> void:
	tower_sprite = Sprite2D.new()
	tower_sprite.scale = Vector2.ONE * BASE_PREVIEW_SCALE
	add_child(tower_sprite)

func setup(_tower_type: Towers.Type) -> void: ##binds the preview to one tower definition and seeds its texture plus authored footprint scale
	tower_type = _tower_type
	tower_sprite.texture = Towers.get_tower_preview(_tower_type)
	tower_sprite.scale = _get_preview_scale()

func update_visuals(is_valid: bool, facing: int, tower_position: Vector2i) -> void: ##keeps the preview centred on the placed footprint while reusing the tower resource's authored size
	if not tower_sprite.texture:
		return

	tower_sprite.modulate = VALID_TINT if is_valid else INVALID_TINT
	tower_sprite.rotation = facing * PI * 0.5
	tower_sprite.scale = _get_preview_scale()
	var base_size: Vector2i = Towers.get_tower_size(tower_type)
	var center_offset: Vector2 = (base_size) * Island.CELL_SIZE * 0.5
	if int(facing) % 2 != 0:
		center_offset = Vector2(center_offset.y, center_offset.x)
	tower_sprite.position = Vector2(tower_position * Island.CELL_SIZE) + center_offset
	#trigger the _draw() function to update any custom overlays
	queue_redraw()

func _get_preview_scale() -> Vector2: ##scales preview art by the authored tower footprint so oversized towers no longer render like 1x1 placements
	var prototype: Tower = Towers.get_tower_prototype(tower_type)
	if is_instance_valid(prototype) and is_instance_valid(prototype.graphics):
		return prototype.graphics.scale

	return Vector2.ONE * BASE_PREVIEW_SCALE
