extends Behavior
class_name DrumRiteBehavior

const INFLUENCE_KEY: StringName = &"drum_trigger_group"
const LINEAGE_LABEL: StringName = &"drum_rite_behavior"

@export var rite_marker_effect: EffectPrototype ##hidden marker used by shared rite-affinity systems such as night lily
@export var topology: TowerTopologyConfig = TowerTopologyConfig.new() ##authored topology whose towers can trigger and receive echoed attacks
@export var echo_bolt_color: Color = Color(0.24, 0.56, 1.0, 1.0) ##blue hue applied to the source-to-target command bolt

var _connected_neighbors: Dictionary[Tower, bool] = {}
var _seen_attack_ids: Dictionary[int, bool] = {}
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null

func start() -> void:
	attach()

func detach() -> void:
	_unsubscribe()
	var to_remove: Array[Tower] = []
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_neighbors.keys())
	for tower: Tower in connected_towers:
		_disconnect_neighbor(tower)
		to_remove.append(tower)

	for tower: Tower in to_remove:
		_connected_neighbors.erase(tower)

	_seen_attack_ids.clear()
	clear_tower_influences()

func attach() -> void:
	_subscribe()

func _subscribe() -> void: ##subscribes the drum to its authored trigger topology
	if _subscription_id != -1:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	var tower: Tower = unit as Tower
	if topology_service == null or not is_instance_valid(tower):
		return
	_subscription_id = topology_service.subscribe(self, tower, _make_query(), _refresh_connections, true)

func _unsubscribe() -> void: ##removes the live trigger query without depending on island teardown order
	if _subscription_id == -1:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service != null:
		topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1
	_last_report = null

func _make_query() -> TowerTopologyService.Query: ##builds the configured topology or cardinal-adjacency default
	if is_instance_valid(topology):
		return topology.build_query()
	return TowerTopologyService.Query.new()

func _refresh_connections(report: TowerTopologyService.Report) -> void:
	_last_report = report
	sync_tower_influences()
	if report == null:
		return
	var current_set: Dictionary[Tower, bool] = {}
	var adjacent_towers: Array[Tower] = []
	adjacent_towers.assign(report.unique_towers)
	adjacent_towers.erase(unit as Tower)

	for neighbor: Tower in adjacent_towers:
		if not is_instance_valid(neighbor):
			continue

		current_set[neighbor] = true

		if not _connected_neighbors.has(neighbor):
			neighbor.subscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_neighbor_event)
			_connected_neighbors[neighbor] = true
			_modify_marker_stack(neighbor, 1)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(neighbor)

	var to_remove: Array[Tower] = []
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_neighbors.keys())
	for old_t: Tower in connected_towers:
		if not current_set.has(old_t):
			_disconnect_neighbor(old_t)
			to_remove.append(old_t)

	for tower: Tower in to_remove:
		_connected_neighbors.erase(tower)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes every authored topology slot participating in the rite's random attack echo
	var rite_tower: Tower = unit as Tower
	if not is_instance_valid(rite_tower):
		return []
	var report: TowerTopologyService.Report = _last_report
	var topology_service: TowerTopologyService = _get_topology_service()
	if report == null and topology_service != null:
		report = topology_service.query(rite_tower, _make_query())
	if report == null:
		return []
	return [TowerInfluence.for_cells(
		INFLUENCE_KEY,
		TowerInfluence.Kind.TRIGGER,
		_get_report_cells(report),
		rite_marker_effect,
	)]

func _on_neighbor_event(event: GameEvent) -> void: ##echoes each eligible primary attack through one different random affected tower
	var hit_data: HitData = event.data as HitData
	if not is_instance_valid(hit_data) or not hit_data.primary:
		return
	if hit_data.has_lineage_producer_label(LINEAGE_LABEL):
		return

	var source_tower: Tower = event.unit as Tower
	if not is_instance_valid(source_tower) or not _connected_neighbors.has(source_tower):
		return

	if not HitData.consume_attack_id(hit_data, _seen_attack_ids):
		return

	var target_tower: Tower = _pick_echo_target(source_tower)
	if is_instance_valid(target_tower):
		target_tower.attack_component.queue_next_attack_context(hit_data, self)
		target_tower.attack_component.current_cooldown = 0.0
		unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)
		BuffComponent.play_link_wisp(source_tower, target_tower, echo_bolt_color)
		if is_instance_valid(unit.buff_component):
			unit.buff_component.activate_target(target_tower, "", null, false)

func _pick_echo_target(source_tower: Tower) -> Tower: ##chooses one other active affected attacker without creating a command when no alternative exists
	var candidates: Array[Tower] = []
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_neighbors.keys())
	for tower: Tower in connected_towers:
		if tower == source_tower:
			continue
		if not is_instance_valid(tower) or tower.disabled or tower.current_state != Tower.State.ACTIVE:
			continue
		if not is_instance_valid(tower.attack_component):
			continue
		candidates.append(tower)

	return candidates.pick_random() if not candidates.is_empty() else null

func _disconnect_neighbor(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	if not _connected_neighbors.has(tower):
		return

	tower.unsubscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_neighbor_event)
	_modify_marker_stack(tower, -1)

func _modify_marker_stack(target: Tower, amount: int) -> void:
	if not is_instance_valid(target) or not is_instance_valid(rite_marker_effect):
		return

	var effect_instance: EffectInstance = target.apply_effect(rite_marker_effect, amount)
	if is_instance_valid(effect_instance):
		effect_instance.source = unit

func _exit_tree() -> void:
	detach()

func _get_topology_service() -> TowerTopologyService: ##resolves the run-owned topology service used by tracking and previews
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service
