#amplifier_behavior.gd
extends Behavior
class_name AmplifierBehavior

const INFLUENCE_KEY: StringName = &"adjacent_modifiers"

#--- configuration ---
#assign a modifierdataprototype resource in the inspector to define the buff this amplifier provides.
@export var modifier_prototypes: Array[ModifierDataPrototype] ##modifier that will be applied to adjacent towers (per adjacent amplifier)
@export var topology: TowerTopologyConfig = TowerTopologyConfig.new() ##authored topology receiving the modifiers; defaults to one-cell cardinal adjacency

class AppliedModifiersState extends RefCounted:
	var tower_ref: WeakRef
	var modifiers: Array[Modifier] = []

	func _init(tower: Tower) -> void:
		tower_ref = weakref(tower)

#target nodes may be freed before their amplifier during scene teardown.
var _applied_modifiers: Dictionary[int, AppliedModifiersState] = {}
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null
var attached: bool = false

func detach() -> void: ##unsubscribes and removes every modifier owned by this amplifier
	attached = false
	_unsubscribe()
	_clear_all_modifiers()
	clear_tower_influences()

func attach() -> void: ##starts the authored topology subscription while this amplifier is active
	attached = true
	_subscribe()

#called by the unit chassis after all components are ready.
func start() -> void:
	#this behavior only makes sense on a tower.
	if not unit is Tower:
		push_warning("AmplifierBehavior can only be used on a Tower.")
		set_process(false) #disable this behavior
		return

	attach()

func _subscribe() -> void: ##registers one topology query and requests its initial report
	if _subscription_id != -1 or not attached:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	var tower: Tower = unit as Tower
	if topology_service == null or not is_instance_valid(tower):
		return
	_subscription_id = topology_service.subscribe(self, tower, _make_query(), _on_topology_updated, true)

func _unsubscribe() -> void: ##removes the topology subscription without depending on island teardown order
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

func _on_topology_updated(report: TowerTopologyService.Report) -> void: ##reconciles modifier ownership against the latest deduplicated topology targets
	if not attached:
		return
	_last_report = report
	sync_tower_influences()
	if modifier_prototypes.is_empty():
		_clear_all_modifiers()
		return

	var current_adjacent_towers: Array[Tower] = []
	if report != null:
		current_adjacent_towers.assign(report.unique_towers)
	current_adjacent_towers.erase(unit as Tower)

	var current_tower_ids: Dictionary[int, bool] = {}
	for tower: Tower in current_adjacent_towers:
		if is_instance_valid(tower):
			current_tower_ids[tower.get_instance_id()] = true

	for tower_id: int in _applied_modifiers.keys():
		if not current_tower_ids.has(tower_id):
			_remove_modifiers_from_tower(tower_id)

	for tower: Tower in current_adjacent_towers:
		if not attached:
			return
		if not is_instance_valid(tower):
			continue
		var tower_id: int = tower.get_instance_id()
		if not _applied_modifiers.has(tower_id) or _applied_modifiers[tower_id].modifiers.is_empty():
			_apply_modifier_to_tower(tower)
			if attached and is_instance_valid(tower) and is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)

#this is the canonical cleanup function, called automatically when the tower is destroyed.
func _exit_tree() -> void:
	detach()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes every potential modifier target in the authored topology, including empty slots
	var influences: Array[TowerInfluence] = []
	if not is_instance_valid(unit) or not unit is Tower:
		return influences
	if modifier_prototypes.is_empty():
		return influences
	var report: TowerTopologyService.Report = _last_report
	var topology_service: TowerTopologyService = _get_topology_service()
	if report == null and topology_service != null:
		report = topology_service.query(unit as Tower, _make_query())
	if report == null:
		return influences
	influences.append(TowerInfluence.for_cells(
		INFLUENCE_KEY,
		TowerInfluence.Kind.MODIFIER,
		_get_report_cells(report),
		null,
		modifier_prototypes
	))
	return influences

func _apply_modifier_to_tower(target_tower: Tower) -> void: ##owns only the generated modifiers, with a weak reference to their recipient
	if not attached or not is_instance_valid(target_tower) or not is_instance_valid(target_tower.modifiers_component):
		return
	var tower_id: int = target_tower.get_instance_id()
	var state := AppliedModifiersState.new(target_tower)
	_applied_modifiers[tower_id] = state
	for modifier_prototype: ModifierDataPrototype in modifier_prototypes:
		if not attached or _applied_modifiers.get(tower_id) != state:
			break
		if not is_instance_valid(target_tower) or not is_instance_valid(target_tower.modifiers_component):
			break
		var new_modifier := modifier_prototype.generate_modifier()
		#brand the modifier with our host unit's id for clear source tracking.
		new_modifier.source_id = unit.unit_id

		#stat notifications can detach the source synchronously, so record ownership first.
		state.modifiers.append(new_modifier)
		target_tower.modifiers_component.add_modifier(new_modifier)

func _remove_modifiers_from_tower(tower_id: int) -> void: ##releases the record even if the target has already been freed
	var state: AppliedModifiersState = _applied_modifiers.get(tower_id)
	if state == null:
		return

	#forget ownership before removal notifications can re-enter cleanup.
	_applied_modifiers.erase(tower_id)
	var target_tower: Tower = state.tower_ref.get_ref() as Tower
	if not is_instance_valid(target_tower) or not is_instance_valid(target_tower.modifiers_component):
		return
	var target_modifiers: ModifiersComponent = target_tower.modifiers_component
	for modifier: Modifier in state.modifiers:
		if not is_instance_valid(target_modifiers):
			break
		target_modifiers.remove_modifier(modifier)

func _clear_all_modifiers() -> void: ##cleans by scalar ids, independent of target destruction order
	for tower_id: int in _applied_modifiers.keys():
		_remove_modifiers_from_tower(tower_id)
	_applied_modifiers.clear()

func _get_topology_service() -> TowerTopologyService: ##resolves the island topology service used by runtime and preview queries
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service
