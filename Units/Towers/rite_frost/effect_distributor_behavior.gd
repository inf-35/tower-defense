extends Behavior
class_name EffectDistributorBehavior

@export var buff_effect: EffectPrototype ##effect to be distributed to adjacencies
@export_flags("Up", "Right", "Down", "Left") var active_directions: int = 0b1111 ##bitmask to configure adjacencies

var _buffed_neighbors: Array[Tower] = []

func start() -> void:
	if not buff_effect:
		push_warning(self, " - EffectDistributorBehavior: No effect assigned!")
		return
		
	var tower := unit as Tower
	tower.adjacency_updated.connect(_on_adjacency_updated)
	tower.died.connect(_on_death)
	tower.tree_exiting.connect(_on_death)
	print(tower, " effect-distributor-behavior started!")
	_on_adjacency_updated(tower.get_adjacent_towers())

# logic to sync buffs with current grid state
func _on_adjacency_updated(adj_map: Dictionary[Vector2i, Tower]) -> void:
	var current_neighbors: Array[Tower] = []
	var host_tower := unit as Tower
	# identify valid neighbours
	for adjacency: Vector2i in adj_map:
		if not _is_local_direction_allowed(host_tower.facing, adjacency):
			continue #reject invalid directions
		
		var tower: Tower = adj_map[adjacency]
		if is_instance_valid(tower) and not tower.is_queued_for_deletion(): #ignore towers which are in the process of exiting
			current_neighbors.append(tower)
	
	# handle lost neighbours (revoke effects)
	for old_tower: Tower in _buffed_neighbors:
		if not current_neighbors.has(old_tower):
			_modify_stack(old_tower, -1)
			
	# handle new neighbours (add buffs)
	for new_tower: Tower in current_neighbors:
		if not _buffed_neighbors.has(new_tower):
			_modify_stack(new_tower, 1)
			
	_buffed_neighbors = current_neighbors
func _is_local_direction_allowed(host_facing: Tower.Facing, grid_dir: Vector2i) -> bool:
	var grid_idx: Tower.Facing
	match grid_dir:
		Vector2i(0, -1): grid_idx = Tower.Facing.UP
		Vector2i(1, 0):  grid_idx = Tower.Facing.RIGHT
		Vector2i(0, 1):  grid_idx = Tower.Facing.DOWN
		Vector2i(-1, 0): grid_idx = Tower.Facing.LEFT
		_: return false #invalid vector

	# calculate local index relative to facing
	var local_idx: int = (grid_idx - host_facing + 4) % 4
	
	# check bitmask
	# we shift 1 by the local index to match the @export_flags order
	var mask_bit: int = 1 << local_idx
	
	return (active_directions & mask_bit) != 0

# helper to add/remove stacks safely
func _modify_stack(target: Tower, amount: int) -> void:
	if not is_instance_valid(target):
		return
	print(target," ",amount," adjacency stacks mdoified")
	# check if target already has effect
	var instance: EffectInstance = target.get_effect_instance_by_prototype(buff_effect)
	
	if amount > 0:
		if instance:
			instance.stacks += 1 #add stacks
		else:
			target.apply_effect(buff_effect) #apply new buff
	else: #removing stacks
		if instance:
			instance.stacks += amount #decrease stack
			# if stacks hit 0, remove the effect entirely
			if instance.stacks <= 0:
				target.remove_effect(buff_effect)

# cleanup: when this tower is sold/destroyed/upgraded
func _on_death(_hit_report_data: HitReportData = null) -> void:
	# revoke our contribution from all current neighbors
	for t in _buffed_neighbors:
		_modify_stack(t, -1)
	_buffed_neighbors.clear()
	
	var tower := unit as Tower
	tower.adjacency_updated.disconnect(_on_adjacency_updated)
	tower.died.disconnect(_on_death)
	tower.tree_exiting.disconnect(_on_death)
