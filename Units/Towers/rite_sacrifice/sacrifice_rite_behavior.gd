extends Behavior
class_name SacrificeRiteBehavior

const INFLUENCE_KEY: StringName = &"watched_towers"

@export var buff_modifier: ModifierDataPrototype ##modifier granted to watched towers when any watched tower is damaged
@export var topology: TowerTopologyConfig = TowerTopologyConfig.new() ##authored topology containing watched and buffed towers

var _subscription_id: int = -1
var _tracked_callbacks: Dictionary[int, Callable] = {} ##int: tower instance id, callable: bound tower damage listener
var _tracked_tower_refs: Dictionary[int, WeakRef] = {} ##int: tower instance id, weakref: watched tower
var _active_modifiers: Dictionary[int, Modifier] = {} ##int: tower unit id, modifier: active wave buff owned by this rite
var _active_tower_refs: Dictionary[int, WeakRef] = {} ##int: tower unit id, weakref: tower receiving the active wave buff
var _active_stack_counts: Dictionary[int, int] = {} ##int: tower unit id, int: number of sacrifice triggers folded into that tower's wave buff
var _last_report: TowerTopologyService.Report = null

func start() -> void:
	if not buff_modifier:
		push_warning("SacrificeRiteBehavior: missing buff_modifier!")

	_connect_wave_end()
	attach()

func attach() -> void:
	_connect_wave_end()
	_subscribe()

func _connect_wave_end() -> void:
	if not Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.connect(_on_wave_ended)

func _make_query() -> TowerTopologyService.Query:
	if is_instance_valid(topology):
		return topology.build_query()
	return TowerTopologyService.Query.new()

func _subscribe() -> void:
	if _subscription_id != -1:
		return

	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service == null:
		return

	_subscription_id = topology_service.subscribe(
		self,
		unit as Tower,
		_make_query(),
		_on_topology_updated,
		true
	)

func _on_topology_updated(report: TowerTopologyService.Report) -> void: ##syncs the set of towers whose damage can trigger and receive the sacrifice buff
	_last_report = report
	sync_tower_influences()
	if buff_modifier == null:
		return
	var new_tracked: Array[Tower] = []
	var new_tracked_ids: Array[int] = []

	for candidate: Object in report.unique_towers:
		if not is_instance_valid(candidate):
			continue
		var t: Tower = candidate as Tower
		if t == null:
			continue
		if t != unit and t.type != Towers.Type.VOID:
			new_tracked.append(t)
			new_tracked_ids.append(t.get_instance_id())

	var tracked_tower_ids: Array[int] = []
	tracked_tower_ids.assign(_tracked_callbacks.keys())
	for old_tower_id: int in tracked_tower_ids:
		if not new_tracked_ids.has(old_tower_id):
			_disconnect_tracked_tower(old_tower_id)

	for new_t: Tower in new_tracked:
		if not _tracked_callbacks.has(new_t.get_instance_id()):
			_connect_tracked_tower(new_t)

func _connect_tracked_tower(tower: Tower) -> void: ##tracks a tower by instance id so teardown can survive freed object refs
	if not is_instance_valid(tower):
		return

	var tower_id: int = tower.get_instance_id()
	var callback: Callable = _on_target_hit.bind(tower)
	tower.subscribe_event(GameEvent.EventType.HIT_RECEIVED, callback)
	_tracked_callbacks[tower_id] = callback
	_tracked_tower_refs[tower_id] = weakref(tower)
	if is_instance_valid(unit.buff_component):
		unit.buff_component.activate_new_link(tower)

func _disconnect_tracked_tower(tower_id: int) -> void: ##disconnects tracked towers without passing freed object keys through typed calls
	if not _tracked_callbacks.has(tower_id):
		_tracked_tower_refs.erase(tower_id)
		return

	var callback: Callable = _tracked_callbacks[tower_id]
	var tower_ref: WeakRef = _tracked_tower_refs.get(tower_id, null)
	var tower: Tower = null
	if tower_ref != null:
		tower = tower_ref.get_ref() as Tower

	if is_instance_valid(tower):
		tower.unsubscribe_event(GameEvent.EventType.HIT_RECEIVED, callback)
	_tracked_callbacks.erase(tower_id)
	_tracked_tower_refs.erase(tower_id)

func _on_target_hit(event: GameEvent, victim: Tower) -> void: ##shows the damaged input reaching the rite before granting one stack to every watched tower
	var hit: HitData = event.data as HitData
	if not hit or hit.damage <= 0.0:
		return

	BuffComponent.play_link_wisp(victim, unit)
	_apply_range_wave_buff()
	unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _apply_range_wave_buff() -> void:
	var report: TowerTopologyService.Report = _get_current_report()
	if report == null:
		return
	for tower: Tower in report.unique_towers:
		_apply_buff_to_tower(tower)
		if is_instance_valid(unit.buff_component):
			unit.buff_component.activate_target(tower)

func _apply_buff_to_tower(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	if tower.hostile or tower.current_state != Tower.State.ACTIVE:
		return
	if not is_instance_valid(tower.modifiers_component):
		return

	var tower_id: int = tower.unit_id
	if _active_modifiers.has(tower_id):
		_active_stack_counts[tower_id] = _active_stack_counts.get(tower_id, 1) + 1
		var active_modifier: Modifier = _active_modifiers[tower_id]
		buff_modifier.apply_single_source_stacks(active_modifier, _active_stack_counts[tower_id])
		tower.modifiers_component.change_modifier(active_modifier)
		return

	var modifier: Modifier = buff_modifier.generate_modifier()
	modifier.cooldown = -1.0
	modifier.source_id = unit.unit_id
	tower.modifiers_component.add_modifier(modifier)
	_active_modifiers[tower_id] = modifier
	_active_tower_refs[tower_id] = weakref(tower)
	_active_stack_counts[tower_id] = 1

func _on_wave_ended(_wave: int) -> void:
	_clear_wave_buffs()

func _clear_wave_buffs() -> void:
	for tower_id: int in _active_modifiers:
		var tower_ref: WeakRef = _active_tower_refs.get(tower_id, null)
		var tower: Tower = null
		if tower_ref != null:
			tower = tower_ref.get_ref() as Tower
		var modifier: Modifier = _active_modifiers[tower_id]
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			tower.modifiers_component.remove_modifier(modifier)

	_active_modifiers.clear()
	_active_tower_refs.clear()
	_active_stack_counts.clear()

func _get_current_report() -> TowerTopologyService.Report:
	if _last_report != null:
		return _last_report
	if not is_instance_valid(unit):
		return null

	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service == null:
		return null

	return topology_service.query(unit as Tower, _make_query())

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes every watched slot using the same query that drives sacrifice's runtime subscriptions
	if buff_modifier == null:
		return []
	var report: TowerTopologyService.Report = _get_current_report()
	if report == null:
		return []
	var modifier_prototypes: Array[ModifierDataPrototype] = [buff_modifier]
	return [TowerInfluence.for_cells(
		INFLUENCE_KEY,
		TowerInfluence.Kind.EFFECT,
		_get_report_cells(report),
		null,
		modifier_prototypes
	)]

func detach() -> void: ##clears subscriptions and wave-long state when the rite leaves active play
	var topology_service: TowerTopologyService = _get_topology_service()
	if _subscription_id != -1:
		if topology_service != null:
			topology_service.unsubscribe(self, _subscription_id)
		_subscription_id = -1

	_clear_wave_buffs()
	var tracked_tower_ids: Array[int] = []
	tracked_tower_ids.assign(_tracked_callbacks.keys())
	for tower_id: int in tracked_tower_ids:
		_disconnect_tracked_tower(tower_id)
	clear_tower_influences()

func _exit_tree() -> void:
	if Run.is_run_ready() and is_instance_valid(Run.phases) and Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.disconnect(_on_wave_ended)
	detach()

func _get_topology_service() -> TowerTopologyService:
	if not is_instance_valid(Run.references):
		return null
	if not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service
