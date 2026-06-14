extends Node
#terrain_service.gd (autoload singleton)
#applies a block of new terrain data to the island
func expand_island(island: Island, block: Dictionary[Vector2i, Terrain.CellData]) -> void:
	var terrain_changes: Dictionary = {}
	for cell: Vector2i in block:
		var cell_data: Terrain.CellData = block[cell]
		#apply terrain base
		island.terrain_base_grid[cell] = cell_data.terrain
		#check if a tower needs to be constructed as part of the expansion
		if cell_data.feature != Towers.Type.VOID and Terrain.is_constructable(cell_data.terrain):
			island.construct_tower_at(cell, cell_data.feature, Tower.Facing.UP, cell_data.initial_state)
		#update renderer
		terrain_changes[cell] = cell_data.terrain

		#this function (in terrainrenderer) checks terrain.get_icon(type)
		#and spawns a sprite if a texture exists.
		island.terrain_renderer.update_decoration(cell, cell_data.terrain)

	island.update_shore_boundary()
	island.update_navigation_grid()
	island.update_lake_preview()
	island.terrain_changed.emit()
	island.terrain_renderer.apply_terrain_changes(terrain_changes)

#checks if a tower can be built on a specific cell
func is_area_constructable(island: Island, tower_facing: Tower.Facing, tower_position: Vector2i, tower_type: Towers.Type, general: bool = false, exclude_tower: Tower = null) -> bool:
	if general: #includes player-side construction checks
		if not Towers.is_tower_upgrade(tower_type):
			#if Towers.is_tower_rite(tower_type) and Run.player.get_rite_count(tower_type) <= 0:
				#return false

			if not Run.player.unlocked_towers.get(tower_type, false):
				return false

			if Run.player.flux < Towers.get_tower_cost(tower_type):
				return false

		var limit: int = Run.player.get_tower_limit(tower_type)
		if limit != -1:
			var current_count: int = island.get_towers_by_type(tower_type).size()
			if current_count >= limit:
				return false

		var used_capacity: float = Run.player.used_capacity
		if exclude_tower:
			used_capacity -= Towers.get_tower_capacity(exclude_tower.type) #exclude excluded tower from capacity computation

		if not (tower_type == Towers.Type.GENERATOR and Run.references.island.get_terrain_base(tower_position) == Terrain.Base.SETTLEMENT): #TODO: fix this for non-1x1 generators
			if used_capacity + Towers.get_tower_capacity(tower_type) > Run.player.tower_capacity and not is_zero_approx(Towers.get_tower_capacity(tower_type)): #and make this non-hardcoded
				return false

	var size: Vector2i = Towers.get_tower_size(tower_type)
	if int(tower_facing) % 2 != 0:
		size = Vector2i(size.y, size.x)

	#fetch specific restrictions for this tower
	var validity: Dictionary = Towers.get_tower_prototype(tower_type).check_placement_validity(island, tower_position, tower_facing)
	if not (validity.has("valid") and validity.valid):
		return false

	var allowed_terrains: Array[Terrain.Base] = Towers.get_tower_allowed_terrains(tower_type)
	for x: int in size.x:
		for y: int in size.y:
			var cell: Vector2i = Vector2i(x,y) + tower_position

			if not island.terrain_base_grid.has(cell):
				return false #cannot build outside the map
			if island.tower_grid.has(cell):
				if not (is_instance_valid(exclude_tower) and island.tower_grid[cell] == exclude_tower):
					return false #cannot build on an existing tower

			var terrain: Terrain.Base = island.terrain_base_grid[cell]

			#--- new: specific terrain check ---
			if not allowed_terrains.is_empty():
				if not allowed_terrains.has(terrain):
					return false
			#-----------------------------------

			#fallback: general constructability check

			if not Terrain.is_constructable(island.terrain_base_grid[cell]):
				return false
	return true

#returns an empty string if valid, or an error description if invalid
func get_construction_error_message(island: Island, cell: Vector2i, tower: Tower) -> String: ##returns the first placement failure reason using shared keyword formatting for actionable resource shortfalls
	var tower_type: Towers.Type = tower.type
	#1. check costs
	if Run.player.flux < Towers.get_tower_cost(tower_type):
		return KeywordService.wrap_bad_text("Insufficient Gold")

	#2. check capacity
	#skip capacity check for generators usually, or if limit logic applies
	if not (tower_type == Towers.Type.GENERATOR and island.get_terrain_base(cell) == Terrain.Base.SETTLEMENT):
		var cap_cost = Towers.get_tower_capacity(tower_type)
		if Run.player.used_capacity + cap_cost > Run.player.tower_capacity and not is_zero_approx(cap_cost):
			return KeywordService.wrap_bad_text("Not enough") + " {POPULATION|icon_size=20|label=Population|color=%s} (%s %s)" % [
				KeywordService.get_bad_color_hex(),
				KeywordService.wrap_highlight_action_text("build"),
				"{T_GENERATOR|icon_size=24|label=Villages|color=%s}" % KeywordService.get_highlight_action_color_hex()
			]

	#3. check limits
	var limit = Run.player.get_tower_limit(tower_type)
	if limit != -1:
		if island.get_towers_by_type(tower_type).size() >= limit:
			return "Placement Limit Reached (%d)" % limit

	#4. check spatial validity
	var size := tower.size
	#(rotation logic should be applied to size before calling this if dynamic,
	#but for error checking base size is usually okay unless fitting in a tight spot)
	var allowed_terrains: Array[Terrain.Base] = Towers.get_tower_allowed_terrains(tower_type)
	#bug: this logic doesnt care about rotation?
	var validity: Dictionary = Towers.get_tower_prototype(tower_type).check_placement_validity(island, cell, tower.facing)
	if validity.has("valid") and not validity.valid:
		return validity.error

	for x in range(size.x):
		for y in range(size.y):
			var check_cell = cell + Vector2i(x, y)

			if not island.terrain_base_grid.has(check_cell):
				return "Out of Bounds"

			if island.tower_grid.has(check_cell):
				return "Location Blocked"

			var terrain = island.terrain_base_grid[check_cell]

			if not allowed_terrains.is_empty():
				if not allowed_terrains.has(terrain):
					#generate nice error message
					var required_names = []
					for t in allowed_terrains:
						required_names.append(Terrain.Base.keys()[t].capitalize())
					return "Requires: %s" % "/".join(required_names)

			if not Terrain.is_constructable(terrain):
				return "Invalid Terrain: %s" % Terrain.Base.keys()[terrain].capitalize()

	return "" #no error
