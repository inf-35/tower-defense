extends Behavior
class_name SaltRiteBehavior

const DAMAGE_INFLUENCE_KEY: StringName = &"salt_damage"
const ATTACK_RATE_INFLUENCE_KEY: StringName = &"salt_attack_rate"

@export var damage_modifier: ModifierDataPrototype
@export var attack_rate_modifier: ModifierDataPrototype
@export var topology: TowerTopologyConfig = TowerTopologyConfig.new() ##authored topology whose vertical and horizontal targets receive their respective modifiers

class AppliedModifierState extends RefCounted:
	var tower_ref: WeakRef
	var modifier: Modifier

	func _init(tower: Tower, applied_modifier: Modifier) -> void:
		tower_ref = weakref(tower)
		modifier = applied_modifier

var _affected_towers: Dictionary[int, AppliedModifierState] = {}
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report

func start() -> void:
	_subscribe()

func attach() -> void:
	_subscribe()

func detach() -> void:
	_unsubscribe()
	_clear_modifiers()
	clear_tower_influences()

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
	if is_instance_valid(topology):
		return topology.build_query()
	return TowerTopologyService.Query.new()

func _on_topology_updated(report: TowerTopologyService.Report) -> void:
	_last_report = report
	sync_tower_influences()
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

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes salt's vertical damage and horizontal attack-rate relationships separately
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return []
	var report: TowerTopologyService.Report = _last_report
	if report == null and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(tower, _make_query())
	if report == null:
		return []

	var damage_cells: Array[Vector2i] = []
	var attack_rate_cells: Array[Vector2i] = []
	for offset: Vector2i in report.cells:
		if offset.x == 0:
			damage_cells.append(report.cells[offset])
		elif offset.y == 0:
			attack_rate_cells.append(report.cells[offset])

	var damage_modifiers: Array[ModifierDataPrototype] = []
	if is_instance_valid(damage_modifier):
		damage_modifiers.append(damage_modifier)

	var attack_rate_modifiers: Array[ModifierDataPrototype] = []
	if is_instance_valid(attack_rate_modifier):
		attack_rate_modifiers.append(attack_rate_modifier)
	return [
		TowerInfluence.for_cells(
			DAMAGE_INFLUENCE_KEY,
			TowerInfluence.Kind.MODIFIER,
			damage_cells,
			null,
			damage_modifiers,
			false,
			TowerInfluence.Scope.TOWER,
			TowerInfluence.VisualRole.POSITIVE
		),
		TowerInfluence.for_cells(
			ATTACK_RATE_INFLUENCE_KEY,
			TowerInfluence.Kind.NEGATIVE,
			attack_rate_cells,
			null,
			attack_rate_modifiers,
			false,
			TowerInfluence.Scope.TOWER,
			TowerInfluence.VisualRole.NEGATIVE
		),
	]

func _get_modifier_for_offset(offset: Vector2i) -> ModifierDataPrototype:
	if offset.x == 0:
		return damage_modifier

	if offset.y == 0:
		return attack_rate_modifier

	return null

func _sync_affected_towers(current_modifiers: Dictionary[Tower, ModifierDataPrototype]) -> void: ##reconciles current topology against weakly tracked modifier ownership
	var current_tower_ids: Dictionary[int, bool] = {}
	for tower: Tower in current_modifiers:
		if is_instance_valid(tower):
			current_tower_ids[tower.get_instance_id()] = true

	var affected_tower_ids: Array[int] = []
	affected_tower_ids.assign(_affected_towers.keys())
	for tower_id: int in affected_tower_ids:
		if not current_tower_ids.has(tower_id):
			_remove_modifier(tower_id)

	for tower: Tower in current_modifiers:
		if not is_instance_valid(tower):
			continue
		var tower_id: int = tower.get_instance_id()
		var modifier_prototype: ModifierDataPrototype = current_modifiers[tower]
		if not _affected_towers.has(tower_id):
			_apply_modifier(tower, modifier_prototype)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)
			continue

		var current_modifier: Modifier = _affected_towers[tower_id].modifier
		if current_modifier.attribute != modifier_prototype.attribute:
			_remove_modifier(tower_id)
			_apply_modifier(tower, modifier_prototype)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)

func _apply_modifier(tower: Tower, modifier_prototype: ModifierDataPrototype) -> void: ##applies and weakly tracks one modifier without owning the target tower's lifetime
	if modifier_prototype == null or not is_instance_valid(tower) or not is_instance_valid(tower.modifiers_component):
		return

	var modifier: Modifier = modifier_prototype.generate_modifier()
	modifier.source_id = unit.unit_id
	tower.modifiers_component.add_modifier(modifier)
	_affected_towers[tower.get_instance_id()] = AppliedModifierState.new(tower, modifier)

func _remove_modifier(tower_id: int) -> void: ##removes tracked state by stable scalar key and cleans the live tower when it still exists
	if not _affected_towers.has(tower_id):
		return

	var state: AppliedModifierState = _affected_towers[tower_id]
	var tower: Tower = state.tower_ref.get_ref() as Tower
	if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
		tower.modifiers_component.remove_modifier(state.modifier)

	_affected_towers.erase(tower_id)

func _clear_modifiers() -> void: ##clears every live modifier and safely drops records whose tower has already been freed
	var affected_tower_ids: Array[int] = []
	affected_tower_ids.assign(_affected_towers.keys())
	for tower_id: int in affected_tower_ids:
		_remove_modifier(tower_id)

	_affected_towers.clear()
