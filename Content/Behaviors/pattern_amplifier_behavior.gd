extends AmplifierBehavior
class_name PatternAmplifierBehavior

@export var query_kind: TowerTopologyService.QueryKind = TowerTopologyService.QueryKind.AXIAL_LINE
@export var min_range: int = 1
@export var max_range: int = 3
@export_flags("Up", "Right", "Down", "Left") var active_directions: int = 0b1111
@export var offsets: Array[Vector2i] = []
@export_enum("World", "Local Facing") var axis_space: int = TowerTopologyService.AxisSpace.LOCAL_FACING

var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report

func start() -> void:
	if not unit is Tower:
		push_warning("PatternAmplifierBehavior can only be used on a Tower.")
		set_process(false)
		return
	attach()

func attach() -> void:
	attached = true
	_subscribe()
	_refresh_report()

func detach() -> void:
	attached = false
	_unsubscribe()
	_clear_all_modifiers()
	clear_tower_influences()
	_last_report = null

func _exit_tree() -> void:
	_unsubscribe()
	_clear_all_modifiers()
	clear_tower_influences()

func _subscribe() -> void:
	if _subscription_id != -1 or not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	_subscription_id = Run.references.island.topology_service.subscribe(self, unit as Tower, _make_query(), _on_topology_updated, false)

func _unsubscribe() -> void:
	if _subscription_id == -1 or not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		_subscription_id = -1
		return
	Run.references.island.topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1

func _make_query() -> TowerTopologyService.Query:
	var query_min := min_range
	var query_max := max_range
	if query_kind == TowerTopologyService.QueryKind.OFFSET_MASK:
		query_min = 0
		query_max = 0
	return TowerTopologyService.Query.new(
		query_kind,
		query_min,
		query_max,
		active_directions,
		offsets,
		axis_space
	)

func _refresh_report() -> void:
	if not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	_on_topology_updated(Run.references.island.topology_service.query(unit as Tower, _make_query()))

func _on_topology_updated(report) -> void:
	_last_report = report
	sync_tower_influences()
	if not attached:
		return
	if modifier_prototypes.is_empty():
		_clear_all_modifiers()
		return

	var current_towers = report.unique_towers
	var towers_to_unmodify: Array[Tower] = []
	for affected_tower: Tower in _applied_modifiers:
		if not current_towers.has(affected_tower):
			towers_to_unmodify.append(affected_tower)
	for tower: Tower in towers_to_unmodify:
		_remove_modifiers_from_tower(tower)
	for tower: Tower in current_towers:
		if not _applied_modifiers.has(tower) or _applied_modifiers[tower].is_empty():
			_apply_modifier_to_tower(tower)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(tower)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the configured topology pattern through the shared modifier relationship surface
	var influences: Array[TowerInfluence] = []
	var report: TowerTopologyService.Report = _last_report
	if report == null and is_instance_valid(unit) and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(unit as Tower, _make_query())
	if report == null or modifier_prototypes.is_empty():
		return influences
	influences.append(TowerInfluence.for_cells(
		INFLUENCE_KEY,
		TowerInfluence.Kind.MODIFIER,
		_get_report_cells(report),
		null,
		modifier_prototypes
	))
	return influences
