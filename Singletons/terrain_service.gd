extends Node
#terain_service.gd (autoload singleton)
# applies a block of new terrain data to the island
func expand_island(island: Island, block: Dictionary) -> void:
	for cell: Vector2i in block:
		var cell_data: Dictionary = block[cell]
		# apply terrain base
		island.terrain_base_grid[cell] = cell_data["base"]
		# the concept of terrain level is now obsolete
		#
		## check if a tower needs to be constructed as part of the expansion
		#if cell_data.has("tower_type"):
			#island.construct_tower_at(cell, cell_data["tower_type"])

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
