extends Behavior
class_name TeleportingBehavior

@export var teleport_distance: float = 40.0 ## how many pixels forward to jump
@export var teleport_interval: float = 4.0 ## cooldown in seconds
@export var blink_vfx: StringName = ID.Particles.ENEMY_DEATH_SPARKS ##vfx for teleporting

var _teleport_timer: float = 0.0

func start() -> void:
	super.start()
	# randomize start time slightly so groups don't blink in unison
	_teleport_timer = randf_range(0.0, teleport_interval * 0.5)

func update(delta: float) -> void:
	super.update(delta) # maintain standard movement/attack logic
	
	_teleport_timer += delta
	if _teleport_timer >= teleport_interval:
		if _attempt_teleport():
			_teleport_timer = 0.0

func _attempt_teleport() -> bool:
	if not is_instance_valid(navigation_component) or not is_instance_valid(movement_component):
		return false
		
	# check for valid path
	var path: Array[Vector2i] = navigation_component._path
	if path.is_empty():
		return false
		
	# calculate target point
	var current_idx: int = navigation_component._current_waypoint_index
	var remaining_dist: float = teleport_distance
	var current_pos: Vector2 = unit.global_position
	
	var target_pos: Vector2 = current_pos
	var new_waypoint_idx: int = current_idx
	
	# iterate through future waypoints to find where 'teleport_distance' lands us
	for i in range(current_idx, path.size()):
		var waypoint_pos: Vector2 = Island.cell_to_position(path[i])
		var dist_to_waypoint: float = current_pos.distance_to(waypoint_pos)
		
		if remaining_dist <= dist_to_waypoint:
			# target on segment
			var direction = (waypoint_pos - current_pos).normalized()
			target_pos = current_pos + (direction * remaining_dist)
			new_waypoint_idx = i
			remaining_dist = 0
			break
		else:
			# target is further along, jump to this waypoint and continue
			remaining_dist -= dist_to_waypoint
			current_pos = waypoint_pos
			new_waypoint_idx = i + 1 # We have passed this waypoint
	
	# if we ran out of path (e.g. close to base), snap to the very end
	if remaining_dist > 0 and not path.is_empty():
		target_pos = Island.cell_to_position(path.back())
		new_waypoint_idx = path.size() - 1

	# don't teleport into a wall
	var target_cell: Vector2i = Island.position_to_cell(target_pos)
	if References.island.tower_grid.has(target_cell):
		# determine if the blocking tower allows phasing or is solid
		var tower = References.island.tower_grid[target_cell]
		if tower.blocking:
			return false # abort teleport, wait for next cycle or normal pathfinding to update

	# execute yeleport
	_apply_visuals(unit.global_position, target_pos)
	
	# sync physics and visuals
	movement_component.position = target_pos # Triggers cell update signal

	# tell navigation we skipped ahead, otherwise it tries to walk back to the skipped waypoints
	navigation_component._current_waypoint_index = new_waypoint_idx
	navigation_component._check_for_obstructions()
		
	return true

func _apply_visuals(start_pos: Vector2, end_pos: Vector2) -> void:
	ParticleManager.play_particles(blink_vfx, start_pos)
	ParticleManager.play_particles(blink_vfx, end_pos)
	
	# Optional: Play sound
	# Audio.play_sound(ID.Sounds.TELEPORT, start_pos)
