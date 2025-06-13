extends Node #TerrainGen

func generate_block(block_size: int) -> Dictionary[Vector2i, Terrain.Base]:
	var island: Island = References.island
	var shore_boundary_tiles: Array[Vector2i] = island.shore_boundary_tiles
	var terrain_level_grid: Dictionary[Vector2i, Terrain.Level] = island.terrain_level_grid
	var terrain_base_grid: Dictionary[Vector2i, Terrain.Base] = island.terrain_base_grid
	var DIRS: Array[Vector2i] = island.DIRS
	var generated_tiles: Dictionary[Vector2i, Terrain.Base] = {}

	if shore_boundary_tiles.is_empty():
		shore_boundary_tiles = [ Vector2i.ZERO ]
	
	var start: Vector2i = shore_boundary_tiles.pick_random()

	var to_visit: Array[Vector2i] = [start]
	
	var to_visit_evaluation: Dictionary[Vector2i, float] = {start: start.length_squared() + 0.0}
	var visited: Dictionary[Vector2i, bool] = {}
	var block_candidate_coords: Array[Vector2i] = []	

	while not to_visit.is_empty() and block_candidate_coords.size() < block_size:
		# Select the cell from to_visit with the lowest evaluation score.
		var cell: Vector2i = to_visit[0]
		for cell_candidate: Vector2i in to_visit:
			if to_visit_evaluation[cell_candidate] < to_visit_evaluation[cell]:
				cell = cell_candidate
		#filter candidates --- see if theyre actually eligible to be part of the expansion
		if terrain_level_grid.has(cell) and terrain_level_grid[cell] == Terrain.Level.SEA:
			block_candidate_coords.append(cell)
		# if not SEA, we still "visit" it to allow expansion from it, but don't add it to our block_candidate_coords.
		# explore neighbors of the current cell.
		for d: Vector2i in DIRS:
			var nbr: Vector2i = cell + d
			# neighbor must be SEA on the current island terrain to be considered for expansion.
			if not terrain_level_grid.has(nbr) or terrain_level_grid[nbr] != Terrain.Level.SEA:
				continue
			# if neighbor has already been visited , skip.
			if visited.has(nbr):
				continue
			# if this neighbor hasn't had an evaluation score calculated yet, calculate it and add it to the to_visit list.
			if not to_visit_evaluation.has(nbr):
				to_visit_evaluation[nbr] = nbr.length_squared() * 0.0 + (nbr - start).length_squared() * 2.0 + randf() 
				to_visit.append(nbr) # Add to the list of cells to potentially visit
		# mark the current cell as visited and remove it from the to_visit list.
		visited[cell] = true
		to_visit.erase(cell)
	#now, for all the chosen coordinates, determine their Terrain.Base type.
	for cell_coord: Vector2i in block_candidate_coords:
		generated_tiles[cell_coord] = Terrain.Base.EARTH if randf() > 0.08 else Terrain.Base.RUINS

	return generated_tiles
