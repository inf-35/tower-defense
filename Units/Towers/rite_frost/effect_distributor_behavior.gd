extends Behavior
class_name EffectDistributorBehavior

const INFLUENCE_KEY: StringName = &"distributed_effect"

@export var buff_effect: EffectPrototype ##effect to be distributed to adjacencies
@export var topology: TowerTopologyConfig = TowerTopologyConfig.new() ##authored topology receiving the distributed effect; defaults to one-cell cardinal adjacency

var _buffed_neighbors: Array[Tower] = []
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null
var attached: bool = false

func detach() -> void: ##unsubscribes and revokes this distributor's stack from every previous topology target
	attached = false
	_unsubscribe()
	for tower: Tower in _buffed_neighbors:
		_modify_stack(tower, -1)
	_buffed_neighbors.clear()
	clear_tower_influences()

func attach() -> void: ##subscribes the active tower to its authored topology
	attached = true
	_subscribe()

func start() -> void: ##validates configuration and starts live topology-driven distribution
	if not buff_effect:
		push_warning(self, " - EffectDistributorBehavior: No effect assigned!")
		return
	attach()

func _subscribe() -> void: ##registers one topology subscription and requests an immediate initial report
	if _subscription_id != -1 or not attached:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	var tower: Tower = unit as Tower
	if topology_service == null or not is_instance_valid(tower):
		return
	_subscription_id = topology_service.subscribe(self, tower, _make_query(), _on_topology_updated, true)

func _unsubscribe() -> void: ##removes the live query without assuming the island still exists
	if _subscription_id == -1:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service != null:
		topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1
	_last_report = null

func _make_query() -> TowerTopologyService.Query: ##builds the configured topology or the cardinal-adjacency default
	if is_instance_valid(topology):
		return topology.build_query()
	return TowerTopologyService.Query.new()

func _on_topology_updated(report: TowerTopologyService.Report) -> void: ##reconciles distributed stacks against the latest deduplicated topology targets
	if not attached:
		return
	_last_report = report
	sync_tower_influences()
	if report == null:
		return

	var current_neighbors: Array[Tower] = []
	for tower: Tower in report.unique_towers:
		if tower != unit and is_instance_valid(tower) and not tower.is_queued_for_deletion():
			current_neighbors.append(tower)

	for old_tower: Tower in _buffed_neighbors:
		if not current_neighbors.has(old_tower):
			_modify_stack(old_tower, -1)

	for new_tower: Tower in current_neighbors:
		if not _buffed_neighbors.has(new_tower):
			_modify_stack(new_tower, 1)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(new_tower)

	_buffed_neighbors = current_neighbors

func _modify_stack(target: Tower, amount: int) -> void: ##changes only this distributor's contribution to the target effect stack
	if not is_instance_valid(target):
		return

	var effect_instance := target.apply_effect(buff_effect, amount)
	if effect_instance:
		effect_instance.source = unit

func _exit_tree() -> void:
	detach()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the exact configured topology used by live effect distribution
	var influences: Array[TowerInfluence] = []
	var host_tower: Tower = unit as Tower
	if not is_instance_valid(host_tower):
		return influences
	if not is_instance_valid(buff_effect):
		return influences
	var report: TowerTopologyService.Report = _last_report
	var topology_service: TowerTopologyService = _get_topology_service()
	if report == null and topology_service != null:
		report = topology_service.query(host_tower, _make_query())
	if report == null:
		return influences
	influences.append(TowerInfluence.for_cells(INFLUENCE_KEY, TowerInfluence.Kind.EFFECT, _get_report_cells(report), buff_effect))
	return influences

func _get_topology_service() -> TowerTopologyService: ##resolves the run-owned topology service shared by live subscriptions and preview queries
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service
