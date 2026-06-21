extends Behavior
class_name GlassRiteBehavior

@export var range_tiles: int = 2
@export var attack_rate_modifier: ModifierDataPrototype
@export var max_health_modifier: ModifierDataPrototype

var _affected_towers: Dictionary[Tower, Array] = {}
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report

func start() -> void:
	_subscribe()

func attach() -> void:
	_subscribe()

func detach() -> void:
	_unsubscribe()
	_clear_modifiers()

func _exit_tree() -> void:
	detach()

func _subscribe() -> void:
	if _subscription_id != -1:
		return

	if not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return

	_subscription_id = Run.references.island.topology_service.subscribe(
		self,
		unit as Tower,
		_make_query(),
		_on_topology_updated,
		true
	)

func _unsubscribe() -> void:
	if _subscription_id == -1:
		return

	if is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		Run.references.island.topology_service.unsubscribe(self, _subscription_id)

	_subscription_id = -1
	_last_report = null

func _make_query() -> TowerTopologyService.Query:
	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.CARDINAL_RING,
		1,
		range_tiles,
		TowerTopologyService.ALL_DIRECTIONS,
		[],
		TowerTopologyService.AxisSpace.WORLD
	)

func _is_inside_footprint(offset: Vector2i, host_size: Vector2i) -> bool:
	return offset.x >= 0 and offset.x < host_size.x and offset.y >= 0 and offset.y < host_size.y

func _distance_to_footprint(offset: Vector2i, host_size: Vector2i) -> int:
	var dx: int = 0
	if offset.x < 0:
		dx = -offset.x
	elif offset.x >= host_size.x:
		dx = offset.x - host_size.x + 1

	var dy: int = 0
	if offset.y < 0:
		dy = -offset.y
	elif offset.y >= host_size.y:
		dy = offset.y - host_size.y + 1

	return maxi(dx, dy)

func _on_topology_updated(report: TowerTopologyService.Report) -> void:
	_last_report = report
	var current_towers: Array[Tower] = []

	for tower: Tower in report.unique_towers:
		if _can_affect_tower(tower):
			current_towers.append(tower)

	_sync_affected_towers(current_towers)

func _sync_affected_towers(current_towers: Array[Tower]) -> void:
	for tower: Tower in _affected_towers.keys():
		if not current_towers.has(tower):
			_remove_modifiers(tower)

	for tower: Tower in current_towers:
		if not _affected_towers.has(tower):
			_apply_modifiers(tower)

			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)

func _can_affect_tower(tower: Tower) -> bool:
	if not is_instance_valid(tower):
		return false

	if tower == unit or tower.hostile or tower.environmental or tower.abstractive:
		return false

	if tower.current_state != Tower.State.ACTIVE:
		return false

	if Towers.is_tower_rite(tower.type):
		return false

	if not is_instance_valid(tower.modifiers_component):
		return false

	return true

func _apply_modifiers(tower: Tower) -> void:
	var modifiers: Array[Modifier] = []
	if attack_rate_modifier:
		var attack_modifier: Modifier = attack_rate_modifier.generate_modifier()
		tower.modifiers_component.add_modifier(attack_modifier)
		modifiers.append(attack_modifier)

	if max_health_modifier:
		var health_modifier: Modifier = max_health_modifier.generate_modifier()
		tower.modifiers_component.add_modifier(health_modifier)
		modifiers.append(health_modifier)

	_affected_towers[tower] = modifiers

func _remove_modifiers(tower: Tower) -> void:
	if not _affected_towers.has(tower):
		return

	var modifiers: Array = _affected_towers[tower]
	if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
		for modifier: Modifier in modifiers:
			tower.modifiers_component.remove_modifier(modifier)

	_affected_towers.erase(tower)

func _clear_modifiers() -> void:
	for tower: Tower in _affected_towers.keys():
		_remove_modifiers(tower)

	_affected_towers.clear()

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return

	var report: TowerTopologyService.Report = _last_report
	if report == null and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(tower, _make_query())

	if report == null:
		return

	for cell: Vector2i in report.cells.values():
		canvas.preview_cell(cell, canvas.highlight_color)
