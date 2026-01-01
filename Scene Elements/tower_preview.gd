# tower_preview.gd
extends Node2D
class_name TowerPreview

# Get a reference to the child Sprite2D node
var tower_sprite: Sprite2D
var tower_type: Towers.Type

# Define tint colors
const VALID_TINT = Color(1, 1, 1, 0.7)
const INVALID_TINT = Color(1, 0.3, 0.3, 0.7)

func _ready():
	tower_sprite = Sprite2D.new()
	tower_sprite.scale = Vector2(0.1, 0.1)
	add_child(tower_sprite)

# Call this once to set up the preview's visual and data
func setup(_tower_type: Towers.Type):
	tower_type = _tower_type
	tower_sprite.texture = Towers.get_tower_preview(_tower_type)

# Call this every frame to update rotation and validity tint
func update_visuals(is_valid: bool, facing: int, tower_position: Vector2i):
	if not tower_sprite.texture:
		return

	tower_sprite.modulate = VALID_TINT if is_valid else INVALID_TINT
	tower_sprite.rotation = facing * PI * 0.5
	tower_sprite.scale = Vector2(Towers.get_tower_size(tower_type) * Island.CELL_SIZE) / tower_sprite.texture.get_size()
	var base_size: Vector2i = Towers.get_tower_size(tower_type)
	var center_offset: Vector2 = (base_size) * Island.CELL_SIZE * 0.5
	if int(facing) % 2 != 0:
		center_offset = Vector2(center_offset.y, center_offset.x)
	tower_sprite.position = Vector2(tower_position * Island.CELL_SIZE) + center_offset
	# Trigger the _draw() function to update any custom overlays
	queue_redraw()

func _draw():
	if not is_instance_valid(tower_sprite):
		return
	#if not tower_stats:
		#return
	# Draw an overlay, like a range indicator
	if true: #some sort of tower stats condition
		# Only draw the range circle if placement is valid
		if tower_sprite.modulate == VALID_TINT:
			var range_color = Color(1, 1, 1, 0.8)
			# Draw the range circle from the center of the node
			draw_arc(tower_sprite.position, Towers.get_tower_stat(tower_type, Attributes.id.RANGE), 0, TAU, 32, range_color, 1)
