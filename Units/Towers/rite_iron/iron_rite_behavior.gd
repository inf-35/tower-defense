extends Behavior
class_name IronRiteBehavior

const INPUT_INFLUENCE_KEY: StringName = &"iron_input"
const OUTPUT_INFLUENCE_KEY: StringName = &"iron_output"

@export var overkill_transfer_ratio: float = 2.0 ##portion of front-tower overkill added to the back tower's attacks
@export var buff_duration: float = 2.0 ##game-time duration of each independent overkill damage window

var _connected_towers: Dictionary[Tower, bool] = {}

func start() -> void:
	var tower: Tower = unit as Tower
	tower.adjacency_updated.connect(_on_adjacency_updated)
	attach()

func attach() -> void:
	sync_tower_influences()
	_refresh_connections()

func detach() -> void:
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		_disconnect_tower(tower)

	_connected_towers.clear()
	clear_tower_influences()

func _on_adjacency_updated(_adj_map: Dictionary[Vector2i, Tower]) -> void:
	sync_tower_influences()
	_refresh_connections()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes iron's facing-relative overkill input and damage output slots
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return []
	var front_cells: Array[Vector2i] = [rite_tower.tower_position + rite_tower.get_forward_direction()]
	var back_cells: Array[Vector2i] = [rite_tower.tower_position - rite_tower.get_forward_direction()]
	return [
		TowerInfluence.for_cells(INPUT_INFLUENCE_KEY, TowerInfluence.Kind.INPUT, front_cells),
		TowerInfluence.for_cells(OUTPUT_INFLUENCE_KEY, TowerInfluence.Kind.OUTPUT, back_cells),
	]

func _refresh_connections() -> void:
	var current_set: Dictionary[Tower, bool] = {}
	for tower: Tower in _get_linked_towers():
		if not is_instance_valid(tower):
			continue

		current_set[tower] = true
		if _connected_towers.has(tower):
			continue

		tower.subscribe_event(GameEvent.EventType.HIT_DEALT, _on_linked_tower_event)
		_connected_towers[tower] = true
		if is_instance_valid(unit.buff_component):
			unit.buff_component.activate_new_link(tower)

	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		if current_set.has(tower):
			continue
		_disconnect_tower(tower)
		_connected_towers.erase(tower)

func _on_linked_tower_event(event: GameEvent) -> void: ##converts routed front-tower overkill reports into timed back-tower damage windows
	_apply_overkill_window(event.unit as Tower, event.data as HitReportData)

func _apply_overkill_window(source_tower: Tower, report: HitReportData) -> void: ##turns one front-tower overkill report into one independently expiring back-tower damage buff
	if source_tower != _get_front_tower():
		return
	if report == null or report.source != source_tower or report.overkill <= 0.0:
		return

	var back_tower: Tower = _get_back_tower()
	if not is_instance_valid(back_tower):
		return

	var stored_damage: float = report.overkill * maxf(overkill_transfer_ratio, 0.0)
	if stored_damage <= 0.0:
		return

	_add_temporary_damage_modifier(back_tower, stored_damage)
	if is_instance_valid(unit.buff_component):
		unit.buff_component.activate_target(back_tower, "+%s DMG" % snappedf(stored_damage, 0.1))
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _add_temporary_damage_modifier(back_tower: Tower, bonus_damage: float) -> void: ##adds one flat damage modifier whose lifetime overlaps additively with other iron windows
	if not is_instance_valid(back_tower) or not is_instance_valid(back_tower.modifiers_component):
		return

	#timed modifiers may briefly outlive this rite if it is destroyed mid-window
	var modifier := Modifier.new(
		Attributes.id.DAMAGE,
		1.0,
		bonus_damage,
		maxf(buff_duration, 0.0),
		null,
		unit.unit_id
	)
	back_tower.modifiers_component.add_modifier(modifier)

func _get_linked_towers() -> Array[Tower]:
	var linked_towers: Array[Tower] = []
	var front_tower: Tower = _get_front_tower()
	var back_tower: Tower = _get_back_tower()
	if is_instance_valid(front_tower):
		linked_towers.append(front_tower)
	if is_instance_valid(back_tower) and back_tower != front_tower:
		linked_towers.append(back_tower)
	return linked_towers

func _get_front_tower() -> Tower:
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return null
	return _get_tower_at_offset(rite_tower.get_forward_direction())

func _get_back_tower() -> Tower:
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return null
	return _get_tower_at_offset(-rite_tower.get_forward_direction())

func _get_tower_at_offset(offset: Vector2i) -> Tower:
	var rite_tower: Tower = unit as Tower
	var island: Island = Run.references.island
	if not is_instance_valid(rite_tower) or not is_instance_valid(island):
		return null
	return island.get_tower_on_tile(rite_tower.tower_position + offset)

func _disconnect_tower(tower: Tower) -> void:
	if not is_instance_valid(tower) or not _connected_towers.has(tower):
		return

	tower.unsubscribe_event(GameEvent.EventType.HIT_DEALT, _on_linked_tower_event)
