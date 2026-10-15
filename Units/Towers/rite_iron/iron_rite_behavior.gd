extends Behavior
class_name IronRiteBehavior

const INPUT_INFLUENCE_KEY: StringName = &"iron_input"
const OUTPUT_INFLUENCE_KEY: StringName = &"iron_output"

@export var overkill_transfer_ratio: float = 2.0 ##portion of front-tower overkill added to the back tower's attacks
@export var buff_duration: float = 2.0 ##game-time duration of each independent overkill damage window
@export var topology: TowerTopologyConfig = TowerTopologyConfig.new() ##authored facing-relative topology containing the input and output towers

var _connected_towers: Dictionary[Tower, bool] = {}
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null

func start() -> void:
	attach()

func attach() -> void:
	_subscribe()

func detach() -> void:
	_unsubscribe()
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_towers.keys())
	for tower: Tower in connected_towers:
		_disconnect_tower(tower)

	_connected_towers.clear()
	clear_tower_influences()

func _subscribe() -> void: ##subscribes iron to its authored input/output topology
	if _subscription_id != -1:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	var tower: Tower = unit as Tower
	if topology_service == null or not is_instance_valid(tower):
		return
	_subscription_id = topology_service.subscribe(self, tower, _make_query(), _on_topology_updated, true)

func _unsubscribe() -> void: ##removes the live endpoint query without depending on island teardown order
	if _subscription_id == -1:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service != null:
		topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1
	_last_report = null

func _make_query() -> TowerTopologyService.Query: ##builds the configured endpoint topology or cardinal-adjacency default
	if is_instance_valid(topology):
		return topology.build_query()
	return TowerTopologyService.Query.new()

func _on_topology_updated(report: TowerTopologyService.Report) -> void:
	_last_report = report
	sync_tower_influences()
	_refresh_connections()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes iron's facing-relative overkill input and damage output slots
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return []
	var report: TowerTopologyService.Report = _get_current_report()
	if report == null:
		return []
	var forward_offset: Vector2i = rite_tower.get_forward_direction()
	var front_cells: Array[Vector2i] = []
	var back_cells: Array[Vector2i] = []
	if report.cells.has(forward_offset):
		front_cells.append(report.cells[forward_offset])
	if report.cells.has(-forward_offset):
		back_cells.append(report.cells[-forward_offset])
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
	var report: TowerTopologyService.Report = _get_current_report()
	if report == null:
		return null
	return report.towers_by_local_offset.get(rite_tower.get_forward_direction()) as Tower

func _get_back_tower() -> Tower:
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return null
	var report: TowerTopologyService.Report = _get_current_report()
	if report == null:
		return null
	return report.towers_by_local_offset.get(-rite_tower.get_forward_direction()) as Tower

func _disconnect_tower(tower: Tower) -> void:
	if not is_instance_valid(tower) or not _connected_towers.has(tower):
		return

	tower.unsubscribe_event(GameEvent.EventType.HIT_DEALT, _on_linked_tower_event)

func _get_current_report() -> TowerTopologyService.Report: ##returns the subscribed report or performs the same query for previews and event callbacks
	if _last_report != null:
		return _last_report
	var topology_service: TowerTopologyService = _get_topology_service()
	var tower: Tower = unit as Tower
	if topology_service == null or not is_instance_valid(tower):
		return null
	return topology_service.query(tower, _make_query())

func _get_topology_service() -> TowerTopologyService: ##resolves the island topology service shared by endpoint tracking and previews
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service

func _exit_tree() -> void:
	detach()
