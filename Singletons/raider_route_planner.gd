extends RefCounted
class_name RaiderRoutePlanner

static func get_waypoint_cells_for_spawn(spawn_cell: Vector2i, raid_targets: Array[Tower]) -> Array[Vector2i]: ##builds a deterministic nearest-next chain of raid target anchor cells from one spawn
	var remaining_cells: Array[Vector2i] = []
	for tower: Tower in raid_targets:
		if not is_instance_valid(tower):
			continue
		if tower.current_state == Tower.State.RUINED:
			continue
		if not Towers.is_raid_target(tower.type):
			continue
		remaining_cells.append(tower.tower_position)

	var ordered_cells: Array[Vector2i] = []
	var current_anchor: Vector2i = spawn_cell

	while not remaining_cells.is_empty():
		var best_index: int = 0
		for i: int in range(1, remaining_cells.size()):
			if _is_better_candidate(current_anchor, remaining_cells[i], remaining_cells[best_index]):
				best_index = i

		var next_cell: Vector2i = remaining_cells[best_index]
		ordered_cells.append(next_cell)
		remaining_cells.remove_at(best_index)
		current_anchor = next_cell

	return ordered_cells

static func build_path(
	start_cell: Vector2i,
	waypoint_cells: Array[Vector2i],
	ignore_walls: bool,
	blocker_cells: Dictionary = {}
) -> Navigation.PathData: ##stitches together one full raider route from spawn through all waypoints and finally the keep
	var full_path: Array[Vector2i] = []
	var current_start: Vector2i = start_cell
	var leg_goals: Array[Vector2i] = waypoint_cells.duplicate()
	leg_goals.append(Vector2i.ZERO)

	for goal_cell: Vector2i in leg_goals:
		if current_start == goal_cell:
			continue

		var leg_path: Navigation.PathData = Navigation.find_path(current_start, goal_cell, ignore_walls) if blocker_cells.is_empty() or ignore_walls else Navigation.get_hypothetical_path(current_start, goal_cell, blocker_cells, false)
		if leg_path.status != Navigation.PathData.Status.FOUND_PATH:
			return Navigation.PathData.new([], Navigation.PathData.Status.NO_PATH)

		full_path.append_array(leg_path.path)
		current_start = goal_cell

	return Navigation.PathData.new(full_path, Navigation.PathData.Status.FOUND_PATH)

static func _is_better_candidate(origin: Vector2i, candidate: Vector2i, incumbent: Vector2i) -> bool:
	var candidate_manhattan: int = absi(candidate.x - origin.x) + absi(candidate.y - origin.y)
	var incumbent_manhattan: int = absi(incumbent.x - origin.x) + absi(incumbent.y - origin.y)
	if candidate_manhattan != incumbent_manhattan:
		return candidate_manhattan < incumbent_manhattan

	var candidate_distance: int = origin.distance_squared_to(candidate)
	var incumbent_distance: int = origin.distance_squared_to(incumbent)
	if candidate_distance != incumbent_distance:
		return candidate_distance < incumbent_distance

	if candidate.y != incumbent.y:
		return candidate.y < incumbent.y

	return candidate.x < incumbent.x
