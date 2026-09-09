extends Behavior
class_name HarborBehavior

const REQUIRED_WATER_ADJACENCIES: int = 1
const VALID_WATER_INFLUENCE_KEY: StringName = &"harbor_valid_water"
const INVALID_WATER_INFLUENCE_KEY: StringName = &"harbor_invalid_water"
const ADJACENT_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

func check_placement_validity(island: Island, cell: Vector2i, _facing: int) -> Dictionary: ##requires at least one adjacent waterlike tile before this settlement can be placed
	if _count_adjacent_waterlike_tiles(island, cell) >= REQUIRED_WATER_ADJACENCIES:
		return { "valid": true, "error": "" }

	return {
		"valid": false,
		"error": "Must touch at least 1 %s tile" % Terrain.get_open_water_label(),
	}

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes valid and invalid adjacent water checks as visual-only placement relationships
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return []

	var island: Island = Run.references.island if is_instance_valid(Run.references.island) else null
	if not is_instance_valid(island):
		return []

	var valid_cells: Array[Vector2i] = []
	var invalid_cells: Array[Vector2i] = []
	for offset: Vector2i in ADJACENT_OFFSETS:
		var cell: Vector2i = tower.tower_position + offset
		if not island.terrain_base_grid.has(cell):
			continue
		if _is_waterlike_cell(island, cell):
			valid_cells.append(cell)
		else:
			invalid_cells.append(cell)
	return [
		TowerInfluence.for_cells(
			VALID_WATER_INFLUENCE_KEY,
			TowerInfluence.Kind.LINK,
			valid_cells,
			null,
			[],
			false,
			TowerInfluence.Scope.WORLD,
			TowerInfluence.VisualRole.POSITIVE
		),
		TowerInfluence.for_cells(
			INVALID_WATER_INFLUENCE_KEY,
			TowerInfluence.Kind.LINK,
			invalid_cells,
			null,
			[],
			false,
			TowerInfluence.Scope.WORLD,
			TowerInfluence.VisualRole.NEGATIVE,
			0.45
		),
	]

func _count_adjacent_waterlike_tiles(island: Island, cell: Vector2i) -> int: ##counts cardinal adjacent waterlike tiles using the same terrain family matching as other water checks
	if not is_instance_valid(island):
		return 0

	var count: int = 0
	for offset: Vector2i in ADJACENT_OFFSETS:
		if _is_waterlike_cell(island, cell + offset):
			count += 1
	return count

func _is_waterlike_cell(island: Island, cell: Vector2i) -> bool: ##returns true for revealed water-family cells such as water or winter ice
	if not island.terrain_base_grid.has(cell):
		return false
	return Terrain.is_waterlike(island.terrain_base_grid[cell])
