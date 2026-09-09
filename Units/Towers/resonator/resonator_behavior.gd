extends Behavior
class_name ResonatorBehavior

const INPUT_INFLUENCE_KEY: StringName = &"resonator_inputs"
const OUTPUT_INFLUENCE_KEY: StringName = &"resonator_output"

@export var cooldown_advance_percent: float = 1.0 ##1.0 advances by one full output tower cooldown
@export var max_resonances_per_second: float = 3.0 ##maximum times this resonator can command its output tower each second
@export var icon: Texture2D ##icon shown when the resonance fires

var _front_subscription_id: int = -1
var _input_subscription_id: int = -1

var _input_towers: Dictionary[Tower, bool] = {}
var _output_tower: Tower = null
var _seen_attack_ids: Dictionary[int, bool] = {} ##int: attack id, bool: true once this resonator has counted that source attack
var _can_resonate: bool = true
var _resonance_limit_token: int = 0

var _last_front_report: TowerTopologyService.Report = null
var _last_input_report: TowerTopologyService.Report = null

func start() -> void:
	attach()

func attach() -> void:
	_subscribe()

func detach() -> void:
	_resonance_limit_token += 1
	_can_resonate = true
	_unsubscribe()
	_disconnect_all_input_towers()
	_output_tower = null
	_seen_attack_ids.clear()
	clear_tower_influences()

func _make_output_query() -> TowerTopologyService.Query: ##returns the local-facing query for the output tower the resonator's arrow points toward
	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.AXIAL_LINE,
		1,
		1,
		TowerTopologyService.AXIS_UP,
		[],
		TowerTopologyService.AxisSpace.LOCAL_FACING
	)

func _make_input_query() -> TowerTopologyService.Query: ##returns the three non-output adjacent cells as local-facing input slots
	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.CARDINAL_RING,
		1,
		1,
		TowerTopologyService.AXIS_RIGHT | TowerTopologyService.AXIS_DOWN | TowerTopologyService.AXIS_LEFT,
		[],
		TowerTopologyService.AxisSpace.LOCAL_FACING
	)

func _subscribe() -> void: ##subscribes to both directional endpoints
	if _front_subscription_id != -1 or _input_subscription_id != -1:
		return

	var topo: TowerTopologyService = _get_topology_service()
	if topo == null:
		return

	_front_subscription_id = topo.subscribe(self, unit as Tower, _make_output_query(), _on_front_updated, true)
	_input_subscription_id = topo.subscribe(self, unit as Tower, _make_input_query(), _on_inputs_updated, true)

func _unsubscribe() -> void: ##disconnects topology watches if the island is still available
	if _front_subscription_id == -1 and _input_subscription_id == -1:
		return
	var topo: TowerTopologyService = _get_topology_service()

	if _front_subscription_id != -1:
		if topo != null:
			topo.unsubscribe(self, _front_subscription_id)
		_front_subscription_id = -1

	if _input_subscription_id != -1:
		if topo != null:
			topo.unsubscribe(self, _input_subscription_id)
		_input_subscription_id = -1

func _on_front_updated(report: TowerTopologyService.Report) -> void: ##tracks the output tower the resonator points toward
	_last_front_report = report
	sync_tower_influences()

	var new_output: Tower = null
	if not report.unique_towers.is_empty():
		new_output = report.unique_towers[0]

	if new_output == _output_tower:
		return

	_output_tower = new_output
	_prune_output_from_inputs()
	if is_instance_valid(unit.buff_component) and is_instance_valid(_output_tower):
		unit.buff_component.activate_new_link(_output_tower)

func _on_inputs_updated(report: TowerTopologyService.Report) -> void: ##binds the three non-output adjacent towers as resonance inputs
	_last_input_report = report
	sync_tower_influences()

	var current_inputs: Dictionary[Tower, bool] = {}
	for tower: Tower in report.unique_towers:
		if not is_instance_valid(tower):
			continue
		if tower == _output_tower:
			continue
		current_inputs[tower] = true
		if not _input_towers.has(tower):
			_connect_input_tower(tower)

	var known_inputs: Array[Tower] = []
	known_inputs.assign(_input_towers.keys())
	for tower: Tower in known_inputs:
		if not current_inputs.has(tower):
			_disconnect_input_tower(tower)

func _connect_input_tower(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	if tower.is_subscribed_to_event(GameEvent.EventType.HIT_DEALT, _on_input_tower_event):
		_input_towers[tower] = true
		return

	tower.subscribe_event(GameEvent.EventType.HIT_DEALT, _on_input_tower_event)
	_input_towers[tower] = true
	if is_instance_valid(unit.buff_component):
		unit.buff_component.activate_new_link(tower)

func _disconnect_input_tower(tower: Tower) -> void:
	_input_towers.erase(tower)
	if is_instance_valid(tower):
		tower.unsubscribe_event(GameEvent.EventType.HIT_DEALT, _on_input_tower_event)

func _disconnect_all_input_towers() -> void:
	var known_inputs: Array[Tower] = []
	known_inputs.assign(_input_towers.keys())
	for tower: Tower in known_inputs:
		_disconnect_input_tower(tower)

func _prune_output_from_inputs() -> void:
	if not is_instance_valid(_output_tower):
		return
	if _input_towers.has(_output_tower):
		_disconnect_input_tower(_output_tower)

func _on_input_tower_event(event: GameEvent) -> void: ##fires only when an input tower applies at least one status stack
	var report: HitReportData = event.data as HitReportData
	if report == null or report.statuses_applied.is_empty():
		return

	var applied_status: bool = false
	for payload_variant: Variant in report.statuses_applied.values():
		var payload: Vector2 = payload_variant
		if payload.x > 0:
			applied_status = true
			break

	if not applied_status:
		return

	if not HitReportData.consume_attack_id(report, _seen_attack_ids):
		return

	_advance_output_cooldown()

func _advance_output_cooldown() -> void: ##moves the output tower's attack cooldown forward by the configured proportion
	if not is_instance_valid(_output_tower) or not is_instance_valid(_output_tower.attack_component):
		return
	if not _can_resonate:
		return

	var comp: AttackComponent = _output_tower.attack_component
	if not comp.attack_data:
		return

	_start_resonance_limit()
	var max_cd: float = comp.cooldown
	var time_to_advance: float = max_cd * cooldown_advance_percent

	comp.current_cooldown = maxf(0.0, comp.current_cooldown - time_to_advance)

	unit.play_action_squash_stretch()
	if is_instance_valid(unit.buff_component):
		unit.buff_component.activate_target(_output_tower, "", icon)
	if is_instance_valid(animation_player):
		_play_animation(&"cast")

func _start_resonance_limit() -> void:
	if max_resonances_per_second <= 0.0:
		return

	_resonance_limit_token += 1
	var token: int = _resonance_limit_token
	_can_resonate = false
	await Clock.await_game_time(1.0 / max_resonances_per_second)
	if token != _resonance_limit_token or not is_inside_tree():
		return
	_can_resonate = true

func _exit_tree() -> void:
	detach()

func _get_topology_service() -> TowerTopologyService:
	if not is_instance_valid(Run.references):
		return null
	if not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the three input slots and facing output through the shared topology/introspection surface
	var influences: Array[TowerInfluence] = []
	var topo: TowerTopologyService = _get_topology_service()
	if topo == null:
		return influences

	var input_report: TowerTopologyService.Report = _last_input_report
	if input_report == null:
		input_report = topo.query(unit as Tower, _make_input_query())
	var output_report: TowerTopologyService.Report = _last_front_report
	if output_report == null:
		output_report = topo.query(unit as Tower, _make_output_query())

	influences.append(TowerInfluence.for_cells(
		INPUT_INFLUENCE_KEY,
		TowerInfluence.Kind.INPUT,
		_get_report_cells(input_report)
	))
	influences.append(TowerInfluence.for_cells(
		OUTPUT_INFLUENCE_KEY,
		TowerInfluence.Kind.OUTPUT,
		_get_report_cells(output_report)
	))
	return influences
