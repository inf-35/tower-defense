#expansionchoice.gd
class_name ExpansionChoice

#block_data contains world coordinates directly from terraingen.generate_block
#key: vector2i (world_coord), value: terrain.celldata
var block_data: Dictionary[Vector2i, Terrain.CellData] = {}

#an identifier for the choice, e.g., "option_0", "option_1", etc.
var id: int

func _init(p_id: int = 0, p_block_data: Dictionary[Vector2i, Terrain.CellData] = {}) -> void:
	id = p_id
	block_data = p_block_data
