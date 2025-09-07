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
func is_cell_constructable(island: Island, cell: Vector2i, tower_type: Towers.Type) -> bool:
	if not island.terrain_base_grid.has(cell):
		return false # cannot build outside the map
	if island.tower_grid.has(cell):
		return false # cannot build on an existing tower (upgrading is a different logic path)
		
	var base: Terrain.Base = island.terrain_base_grid[cell]
	# use the data repository to check the base's properties
	return Terrain.is_constructable(base)
