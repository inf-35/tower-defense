extends Node
#terrain_service.gd (autoload singleton)
# applies a block of new terrain data to the island
func expand_island(island: Island, block: Dictionary[Vector2i, Terrain.CellData]) -> void:
	for cell: Vector2i in block:
		var cell_data: Terrain.CellData = block[cell]
		# apply terrain base
		island.terrain_base_grid[cell] = cell_data.terrain
		# check if a tower needs to be constructed as part of the expansion
		if cell_data.feature != Towers.Type.VOID:
			island.construct_tower_at(cell, cell_data.feature, Tower.Facing.UP, cell_data.initial_state)

	island.update_shore_boundary()
	island.update_navigation_grid()
	island.terrain_changed.emit()

# checks if a tower can be built on a specific cell
func is_area_constructable(island: Island, tower_position: Vector2i, tower_type: Towers.Type, general: bool = false) -> bool:
	if general: #includes player-side construction checks
		if not Player.unlocked_towers.get(tower_type, false):
			return false
		
		if Player.flux < Towers.get_tower_cost(tower_type):
			return false
			
		if not (tower_type == Towers.Type.GENERATOR and References.island.get_terrain_base(tower_position) == Terrain.Base.RUINS): #TODO: fix this for non-1x1 generators
			if Player.used_capacity + Towers.get_tower_capacity(tower_type) > Player.tower_capacity: #and make this non-hardcoded
				return false
				
	var size: Vector2i = Towers.get_tower_size(tower_type)
	for x: int in size.x:
		for y: int in size.y:
			var cell: Vector2i = Vector2i(x,y) + tower_position	

			if not island.terrain_base_grid.has(cell):
				return false # cannot build outside the map
			if island.tower_grid.has(cell):
				return false # cannot build on an existing tower (upgrading is a different logic path)
			if not Terrain.is_constructable(island.terrain_base_grid[cell]):
				return false
	
	return true
