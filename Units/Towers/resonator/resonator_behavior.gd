extends Behavior
class_name ResonatorBehavior

@export var cooldown_advance_percent: float = 1.0 ##1.0 advances by one full receiver cooldown
@export var max_resonances_per_second: float = 3.0 ##maximum times this resonator can command its receiver each second
@export var icon: Texture2D ##icon shown when the resonance fires

var _front_subscription_id: int = -1
var _back_subscription_id: int = -1

var _trigger_tower: Tower = null
var _receiver_tower: Tower = null
var _seen_attack_ids: Dictionary[int, bool] = {} ##int: attack id, bool: true once this resonator has counted that source attack
var _can_resonate: bool = true
var _resonance_limit_token: int = 0

var _last_front_report: TowerTopologyService.Report = null
var _last_back_report: TowerTopologyService.Report = null

func start() -> void:
	attach()

func attach() -> void:
	_subscribe()

func detach() -> void:
	_resonance_limit_token += 1
	_can_resonate = true
	_unsubscribe()
	_disconnect_trigger_tower()
	_trigger_tower = null
	_receiver_tower = null
	_seen_attack_ids.clear()

func _make_query(is_front: bool) -> TowerTopologyService.Query: ##returns the local-facing query for the trigger or receiver tower
	var axis: int = TowerTopologyService.AXIS_UP if is_front else TowerTopologyService.AXIS_DOWN

	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.AXIAL_LINE,
		1,
		1,
		axis,
		[],
		TowerTopologyService.AxisSpace.LOCAL_FACING
	)

func _subscribe() -> void: ##subscribes to both directional endpoints
	if _front_subscription_id != -1 or _back_subscription_id != -1:
		return

	var topo: TowerTopologyService = _get_topology_service()
	if topo == null:
		return

	_front_subscription_id = topo.subscribe(self, unit as Tower, _make_query(true), _on_front_updated, true)
	_back_subscription_id = topo.subscribe(self, unit as Tower, _make_query(false), _on_back_updated, true)

func _unsubscribe() -> void: ##disconnects topology watches if the island is still available
	if _front_subscription_id == -1 and _back_subscription_id == -1:
		return
	var topo: TowerTopologyService = _get_topology_service()

	if _front_subscription_id != -1:
		if topo != null:
			topo.unsubscribe(self, _front_subscription_id)
		_front_subscription_id = -1

	if _back_subscription_id != -1:
		if topo != null:
			topo.unsubscribe(self, _back_subscription_id)
		_back_subscription_id = -1

func _on_front_updated(report: TowerTopologyService.Report) -> void: ##binds to the tower whose status applications trigger resonance
	_last_front_report = report

	var new_trigger: Tower = null
	if not report.unique_towers.is_empty():
		new_trigger = report.unique_towers[0]

	if _trigger_tower != new_trigger:
		_disconnect_trigger_tower()
		_trigger_tower = new_trigger

		if is_instance_valid(_trigger_tower):
			_trigger_tower.on_event.connect(_on_trigger_tower_event)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(_trigger_tower)

func _disconnect_trigger_tower() -> void:
	if is_instance_valid(_trigger_tower):
		if _trigger_tower.on_event.is_connected(_on_trigger_tower_event):
			_trigger_tower.on_event.disconnect(_on_trigger_tower_event)

func _on_back_updated(report: TowerTopologyService.Report) -> void: ##tracks the tower that receives cooldown advancement
	_last_back_report = report

	var new_receiver: Tower = null
	if not report.unique_towers.is_empty():
		new_receiver = report.unique_towers[0]

	if new_receiver == _receiver_tower:
		return

	_receiver_tower = new_receiver
	if is_instance_valid(unit.buff_component) and is_instance_valid(_receiver_tower):
		unit.buff_component.activate_new_link(_receiver_tower)

func _on_trigger_tower_event(event: GameEvent) -> void: ##fires only when the forward tower applies at least one status stack
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

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

	_advance_receiver_cooldown()

func _advance_receiver_cooldown() -> void: ##moves the rear tower's attack cooldown forward by the configured proportion
	if not is_instance_valid(_receiver_tower) or not is_instance_valid(_receiver_tower.attack_component):
		return
	if not _can_resonate:
		return

	var comp: AttackComponent = _receiver_tower.attack_component
	if not comp.attack_data:
		return

	_start_resonance_limit()
	var max_cd: float = comp.cooldown
	var time_to_advance: float = max_cd * cooldown_advance_percent

	comp.current_cooldown = maxf(0.0, comp.current_cooldown - time_to_advance)

	unit.play_action_squash_stretch()
	UI.floating_text_manager.show_icon(icon, _receiver_tower.global_position)
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

func draw_visuals(canvas: RangeIndicator) -> void:
	var topo: TowerTopologyService = _get_topology_service()
	if topo == null:
		return

	_draw_query_visuals(canvas, topo, _make_query(true), canvas.input_color)
	_draw_query_visuals(canvas, topo, _make_query(false), canvas.highlight_color)

func _draw_query_visuals(
	canvas: RangeIndicator,
	topo: TowerTopologyService,
	query: TowerTopologyService.Query,
	color: Color
) -> void: ##draws one endpoint role with its own color so trigger and receiver read separately
	var margin: int = 2
	var cell_size := Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	var report: TowerTopologyService.Report = topo.query(unit as Tower, query)

	for cell: Vector2i in report.cells.values():
		var rect: Rect2 = Rect2(Island.cell_to_position(cell) - half_size, Vector2(cell_size, cell_size))
		canvas.preview_rect(rect, color, false, 1.0)
