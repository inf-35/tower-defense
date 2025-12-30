extends Node
#terrain_service.gd (autoload singleton)
# applies a block of new terrain data to the island
func expand_island(island: Island, block: Dictionary[Vector2i, Terrain.CellData]) -> void:
	var terrain_changes: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in block:
		var cell_data: Terrain.CellData = block[cell]
		# apply terrain base
		island.terrain_base_grid[cell] = cell_data.terrain
		# check if a tower needs to be constructed as part of the expansion
		if cell_data.feature != Towers.Type.VOID:
			island.construct_tower_at(cell, cell_data.feature, Tower.Facing.UP, cell_data.initial_state)
		# update renderer
		terrain_changes[cell] = true

		# this function (in TerrainRenderer) checks Terrain.get_icon(type)
		# and spawns a sprite if a texture exists.
		island.terrain_renderer.update_decoration(cell, cell_data.terrain)


	island.update_shore_boundary()
	island.update_navigation_grid()
	island.terrain_changed.emit()
	island.terrain_renderer.apply_terrain_changes(terrain_changes)

# checks if a tower can be built on a specific cell
func is_area_constructable(island: Island, tower_facing: Tower.Facing, tower_position: Vector2i, tower_type: Towers.Type, general: bool = false, exclude_tower: Tower = null) -> bool:
	if general: #includes player-side construction checks
		if not Towers.is_tower_upgrade(tower_type):
			if Towers.is_tower_rite(tower_type) and Player.get_rite_count(tower_type) <= 0:
				return false
		
			if not Player.unlocked_towers.get(tower_type, false):
				return false
			
			if Player.flux < Towers.get_tower_cost(tower_type):
				return false
		
		var limit: int = Player.get_tower_limit(tower_type)
		if limit != -1:
			var current_count: int = island.get_towers_by_type(tower_type).size()
			if current_count >= limit:
				return false
				
		var used_capacity: float = Player.used_capacity
		if exclude_tower:
			used_capacity -= Towers.get_tower_capacity(exclude_tower.type) # exclude excluded tower from capacity computation
		
		if not (tower_type == Towers.Type.GENERATOR and References.island.get_terrain_base(tower_position) == Terrain.Base.RUINS): #TODO: fix this for non-1x1 generators
			if used_capacity + Towers.get_tower_capacity(tower_type) > Player.tower_capacity: #and make this non-hardcoded
				return false
				
	var size: Vector2i = Towers.get_tower_size(tower_type)
	if int(tower_facing) % 2 != 0:
		size = Vector2i(size.y, size.x)
	for x: int in size.x:
		for y: int in size.y:
			var cell: Vector2i = Vector2i(x,y) + tower_position	

			if not island.terrain_base_grid.has(cell):
				return false # cannot build outside the map
			if island.tower_grid.has(cell):
				if not (is_instance_valid(exclude_tower) and island.tower_grid[cell] == exclude_tower):
					return false # cannot build on an existing tower
			if not Terrain.is_constructable(island.terrain_base_grid[cell]):
				return false
	
	return true
