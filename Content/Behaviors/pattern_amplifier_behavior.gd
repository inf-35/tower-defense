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
	_last_report = null

func _exit_tree() -> void:
	_unsubscribe()
	_clear_all_modifiers()

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

func draw_visuals(canvas: RangeIndicator) -> void:
	var report = _last_report
	if report == null and is_instance_valid(unit) and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(unit as Tower, _make_query())
	if report == null:
		return

	var margin: int = 2
	var cell_size := Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	for cell: Vector2i in report.cells.values():
		var rect: Rect2 = Rect2(Island.cell_to_position(cell) - half_size, Vector2(cell_size, cell_size))
		canvas.preview_rect(rect, canvas.highlight_color, false, 1.0)
