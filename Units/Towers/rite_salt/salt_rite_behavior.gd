extends Behavior
class_name SaltRiteBehavior

@export var damage_modifier: ModifierDataPrototype
@export var attack_rate_modifier: ModifierDataPrototype

var _affected_towers: Dictionary[Tower, Modifier] = {}
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
		TowerTopologyService.QueryKind.AXIAL_LINE,
		1,
		1,
		TowerTopologyService.ALL_DIRECTIONS,
		[],
		TowerTopologyService.AxisSpace.WORLD
	)

func _on_topology_updated(report: TowerTopologyService.Report) -> void:
	_last_report = report
	var current_modifiers: Dictionary[Tower, ModifierDataPrototype] = {}

	for offset: Vector2i in report.towers_by_local_offset:
		var target_tower: Tower = report.towers_by_local_offset[offset]
		if not is_instance_valid(target_tower) or not is_instance_valid(target_tower.modifiers_component):
			continue

		var modifier_prototype: ModifierDataPrototype = _get_modifier_for_offset(offset)
		if modifier_prototype == null:
			continue

		current_modifiers[target_tower] = modifier_prototype

	_sync_affected_towers(current_modifiers)

func _get_modifier_for_offset(offset: Vector2i) -> ModifierDataPrototype:
	var side: int = Tower.get_side_from_offset((unit as Tower).size, offset)
	var forward: Tower.Facing = (unit as Tower).facing
	if side == forward or side == _get_backward_facing(forward):
		return damage_modifier

	if side != 10:
		return attack_rate_modifier

	return null

func _sync_affected_towers(current_modifiers: Dictionary[Tower, ModifierDataPrototype]) -> void:
	_prune_invalid_affected_towers()

	var affected_towers: Array[Tower] = []
	affected_towers.assign(_affected_towers.keys())
	for tower: Tower in affected_towers:
		if not current_modifiers.has(tower):
			_remove_modifier(tower)

	for tower: Tower in current_modifiers:
		var modifier_prototype: ModifierDataPrototype = current_modifiers[tower]
		if not _affected_towers.has(tower):
			_apply_modifier(tower, modifier_prototype)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)
			continue

		var current_modifier: Modifier = _affected_towers[tower]
		if current_modifier.attribute != modifier_prototype.attribute:
			_remove_modifier(tower)
			_apply_modifier(tower, modifier_prototype)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)

func _apply_modifier(tower: Tower, modifier_prototype: ModifierDataPrototype) -> void:
	if modifier_prototype == null:
		return

	var modifier: Modifier = modifier_prototype.generate_modifier()
	tower.modifiers_component.add_modifier(modifier)
	_affected_towers[tower] = modifier

func _remove_modifier(tower: Tower) -> void:
	if not _affected_towers.has(tower):
		return

	var modifier: Modifier = _affected_towers[tower]
	if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
		tower.modifiers_component.remove_modifier(modifier)

	_affected_towers.erase(tower)

func _clear_modifiers() -> void:
	var affected_towers: Array[Tower] = []
	affected_towers.assign(_affected_towers.keys())
	for tower: Tower in affected_towers:
		_remove_modifier(tower)

	_affected_towers.clear()

func _prune_invalid_affected_towers() -> void: ##drops stale tower keys left behind by sold or destroyed neighbors before sync logic touches them again
	var invalid_towers: Array[Tower] = []
	invalid_towers.assign(_affected_towers.keys())
	for tower: Tower in invalid_towers:
		if is_instance_valid(tower):
			continue
		_affected_towers.erase(tower)

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return

	var report: TowerTopologyService.Report = _last_report
	if report == null and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(tower, _make_query())

	if report == null:
		return

	for offset: Vector2i in report.cells:
		var side: int = Tower.get_side_from_offset(tower.size, offset)
		var color: Color = canvas.positive_highlight_color
		if side != tower.facing and side != _get_backward_facing(tower.facing):
			color = canvas.negative_highlight_color
		canvas.preview_cell(report.cells[offset], color)

func _get_backward_facing(facing: Tower.Facing) -> Tower.Facing:
	return ((facing + 2) % 4) as Tower.Facing
