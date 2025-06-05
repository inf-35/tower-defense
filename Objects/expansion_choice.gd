# ExpansionChoice.gd
class_name ExpansionChoice

# block_data contains world coordinates directly from TerrainGen.generate_block
# Key: Vector2i (world_coord), Value: Terrain.Base
var block_data: Dictionary[Vector2i, Terrain.Base] = {}

# An identifier for the choice, e.g., "option_0", "option_1", etc.
var id: int

func _init(p_id: int = 0, p_block_data: Dictionary = {}):
	id = p_id
	block_data = p_block_data
