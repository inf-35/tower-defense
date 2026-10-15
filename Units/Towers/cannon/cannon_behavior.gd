extends DefaultTowerBehavior
class_name CannonBehavior

const INFLUENCE_KEY: StringName = &"cannon_palisade_range"
@export var RANGE_PER_PALISADE: float = 4.0
@export var attack_rate_per_palisade: float = 0.02 ##flat attacks-per-second bonus gained from each adjacent active palisade
const PALISADE_TYPES: Array[Towers.Type] = [
	Towers.Type.PALISADE,
	Towers.Type.PALISADE_UPGRADE_1,
]

var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null
var _range_modifier: Modifier = null
var _attack_rate_modifier: Modifier = null
var _attached: bool = false

func start() -> void: ##starts normal cannon targeting and its intrinsic palisade-range link
	super.start()
	attach()

func attach() -> void: ##restores topology tracking and the owned range modifier when the cannon becomes active
	if _attached:
		return
	_attached = true

	if is_instance_valid(modifiers_component):
		_range_modifier = Modifier.new(Attributes.id.RANGE, 1.0, 0.0, -1.0, null, unit.unit_id)
		modifiers_component.add_modifier(_range_modifier)
		_attack_rate_modifier = Modifier.new(Attributes.id.ATTACK_RATE, 1.0, 0.0, -1.0, null, unit.unit_id)
		modifiers_component.add_modifier(_attack_rate_modifier)

	var topology_service: TowerTopologyService = _get_topology_service()
	var tower: Tower = unit as Tower
	if topology_service != null and is_instance_valid(tower):
		_subscription_id = topology_service.subscribe(self, tower, TowerTopologyService.Query.new(), _on_topology_updated, true)

	var island: Island = Run.references.island if is_instance_valid(Run.references) else null
	if is_instance_valid(island) and not island.tower_changed.is_connected(_on_island_tower_changed):
		island.tower_changed.connect(_on_island_tower_changed)

	sync_tower_influences()

func detach() -> void: ##removes the intrinsic bonus and every live topology hook while the cannon is inactive
	_attached = false
	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service != null and _subscription_id != -1:
		topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1
	_last_report = null

	var island: Island = Run.references.island if is_instance_valid(Run.references) else null
	if is_instance_valid(island) and island.tower_changed.is_connected(_on_island_tower_changed):
		island.tower_changed.disconnect(_on_island_tower_changed)

	if is_instance_valid(modifiers_component) and is_instance_valid(_range_modifier):
		modifiers_component.remove_modifier(_range_modifier)
	if is_instance_valid(modifiers_component) and is_instance_valid(_attack_rate_modifier):
		modifiers_component.remove_modifier(_attack_rate_modifier)
	_range_modifier = null
	_attack_rate_modifier = null
	clear_tower_influences()

func _on_topology_updated(report: TowerTopologyService.Report) -> void: ##recalculates the flat range bonus from active palisades around the full cannon footprint
	if not _attached:
		return
	_last_report = report
	var palisade_count: int = 0
	if report != null:
		for adjacent_tower: Tower in report.unique_towers:
			if not is_instance_valid(adjacent_tower) or adjacent_tower.current_state != Tower.State.ACTIVE:
				continue
			if PALISADE_TYPES.has(adjacent_tower.type):
				palisade_count += 1

	var range_bonus: float = float(palisade_count) * RANGE_PER_PALISADE
	if is_instance_valid(_range_modifier) and not is_equal_approx(_range_modifier.additive, range_bonus):
		_range_modifier.additive = range_bonus
		modifiers_component.change_modifier(_range_modifier)
	var attack_rate_bonus: float = float(palisade_count) * attack_rate_per_palisade
	if is_instance_valid(_attack_rate_modifier) and not is_equal_approx(_attack_rate_modifier.additive, attack_rate_bonus):
		_attack_rate_modifier.additive = attack_rate_bonus
		modifiers_component.change_modifier(_attack_rate_modifier)
	sync_tower_influences()

func _on_island_tower_changed(_changed_cell: Vector2i) -> void: ##refreshes state-sensitive eligibility because ruined towers remain in the topology grid during combat
	if not _attached:
		return
	var topology_service: TowerTopologyService = _get_topology_service()
	if topology_service != null:
		_on_topology_updated(topology_service.query(unit as Tower, TowerTopologyService.Query.new()))

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##highlights every cell where a palisade can extend the cannon's range
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return []

	var report: TowerTopologyService.Report = _last_report
	var topology_service: TowerTopologyService = _get_topology_service()
	if report == null and topology_service != null:
		report = topology_service.query(tower, TowerTopologyService.Query.new())
	if report == null:
		return []

	return [TowerInfluence.for_cells(
		INFLUENCE_KEY,
		TowerInfluence.Kind.INPUT,
		_get_report_cells(report),
		null,
		[],
		false,
		TowerInfluence.Scope.TOWER,
		TowerInfluence.VisualRole.INPUT
	)]

func _get_topology_service() -> TowerTopologyService: ##resolves the island-owned topology service shared by runtime bonuses and previews
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return null
	if not is_instance_valid(Run.references.island.topology_service):
		return null
	return Run.references.island.topology_service

func _exit_tree() -> void:
	detach()
