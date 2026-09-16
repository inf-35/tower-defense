extends Behavior
class_name EffectDistributorBehavior

const INFLUENCE_KEY: StringName = &"distributed_effect"

@export var buff_effect: EffectPrototype ##effect to be distributed to adjacencies
@export_flags("Up", "Right", "Down", "Left") var active_directions: int = 0b1111 ##bitmask to configure adjacencies

var _buffed_neighbors: Array[Tower] = []
var attached: bool = false

func detach() -> void:
	attached = false
	#revoke our contribution from all current neighbors
	for t in _buffed_neighbors:
		_modify_stack(t, -1)
	_buffed_neighbors.clear()
	clear_tower_influences()

func attach() -> void:
	attached = true
	var tower: Tower = unit as Tower
	if is_instance_valid(tower) and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		_on_adjacency_updated(Run.references.island.topology_service.get_adjacency_report(tower))

func start() -> void:
	if not buff_effect:
		push_warning(self, " - EffectDistributorBehavior: No effect assigned!")
		return

	var tower: Tower = unit as Tower
	tower.adjacency_updated.connect(_on_adjacency_updated)
	tower.tree_exiting.connect(_on_exit)

	attach()

#logic to sync buffs with current grid state
func _on_adjacency_updated(adjacency_data: AdjacencyReportData) -> void:
	if not attached:
		return
	sync_tower_influences()
	if adjacency_data == null:
		return

	var current_neighbors: Array[Tower] = []
	var host_tower: Tower = unit as Tower

	#identify valid neighbours
	for adjacency: Vector2i in adjacency_data.adjacent_towers:
		if not _is_local_direction_allowed(host_tower.facing, adjacency):
			continue #reject invalid directions

		var tower: Tower = adjacency_data.adjacent_towers[adjacency]
		if is_instance_valid(tower) and not tower.is_queued_for_deletion(): #ignore towers which are in the process of exiting
			current_neighbors.append(tower)

	#handle lost neighbours (revoke effects)
	for old_tower: Tower in _buffed_neighbors:
		if not current_neighbors.has(old_tower):
			_modify_stack(old_tower, -1)

	#handle new neighbours (add buffs)
	for new_tower: Tower in current_neighbors:
		if not _buffed_neighbors.has(new_tower):
			_modify_stack(new_tower, 1)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(new_tower)

	_buffed_neighbors = current_neighbors

func _is_local_direction_allowed(host_facing: Tower.Facing, grid_dir: Vector2i) -> bool:
	var grid_idx: Tower.Facing
	grid_idx = Tower.get_side_from_offset(unit.size, grid_dir)

	#calculate local index relative to facing
	var local_idx: int = (grid_idx - host_facing + 4) % 4

	#check bitmask
	#we shift 1 by the local index to match the @export_flags order
	var mask_bit: int = 1 << local_idx

	return (active_directions & mask_bit) != 0

#helper to add/remove stacks safely
func _modify_stack(target: Tower, amount: int) -> void:
	if not is_instance_valid(target):
		return

	var effect_instance := target.apply_effect(buff_effect, amount)
	if effect_instance:
		effect_instance.source = unit

#cleanup: when this tower is sold/destroyed/upgraded
func _on_exit(_hit_report_data: HitReportData = null) -> void:
	#detach is called when the tower dies by default
	var tower: Tower = unit as Tower
	tower.adjacency_updated.disconnect(_on_adjacency_updated)
	tower.tree_exiting.disconnect(_on_exit)
	clear_tower_influences()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the same facing-relative adjacent cells used by live effect distribution
	var influences: Array[TowerInfluence] = []
	var host_tower: Tower = unit as Tower
	if not is_instance_valid(host_tower):
		return influences
	if not is_instance_valid(buff_effect):
		return influences
	var cells: Array[Vector2i] = []
	for cell: Vector2i in host_tower.get_adjacent_cells():
		var offset: Vector2i = cell - host_tower.tower_position
		if _is_local_direction_allowed(host_tower.facing, offset):
			cells.append(cell)
	influences.append(TowerInfluence.for_cells(INFLUENCE_KEY, TowerInfluence.Kind.EFFECT, cells, buff_effect))
	return influences
