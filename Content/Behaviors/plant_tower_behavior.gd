#plant_tower_behavior.gd
extends DefaultTowerBehavior
class_name PlantTowerBehavior

@export var additive_damage_per_forest: float = 0.2

var _forest_modifier: Modifier = null
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report ##adjacency report cache

func start() -> void:
	super.start()
	attach()

func attach() -> void:
	_subscribe()
	_refresh_forest_bonus()

func detach() -> void:
	_unsubscribe()
	if is_instance_valid(modifiers_component) and _forest_modifier != null:
		modifiers_component.remove_modifier(_forest_modifier)
	_forest_modifier = null
	_last_report = null

func _exit_tree() -> void:
	_unsubscribe()

func _subscribe() -> void:
	if _subscription_id != -1:
		return
	if not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	_subscription_id = Run.references.island.topology_service.subscribe(self, unit as Tower, _make_query(), _on_topology_updated, false)

func _unsubscribe() -> void:
	if _subscription_id == -1:
		return
	if is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		Run.references.island.topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1

func _make_query() -> TowerTopologyService.Query:
	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.CARDINAL_RING,
		1,
		2,
		TowerTopologyService.AXIS_UP | TowerTopologyService.AXIS_RIGHT | TowerTopologyService.AXIS_DOWN | TowerTopologyService.AXIS_LEFT,
		[],
		TowerTopologyService.AxisSpace.WORLD
	)

func _refresh_forest_bonus() -> void:
	if not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	_on_topology_updated(Run.references.island.topology_service.query(unit as Tower, _make_query()))

func _on_topology_updated(report) -> void:
	_last_report = report
	if not is_instance_valid(modifiers_component):
		return
	var forest_tiles: int = 0
	for tower: Tower in report.towers_by_local_offset.values():
		if is_instance_valid(tower) and tower.type == Towers.Type.FOREST:
			forest_tiles += 1
	var new_modifier := Modifier.new(Attributes.id.DAMAGE)
	new_modifier.additive = forest_tiles * additive_damage_per_forest
	new_modifier.multiplicative = 1.0
	new_modifier.cooldown = -1.0
	modifiers_component.replace_modifier(_forest_modifier, new_modifier)
	_forest_modifier = new_modifier

func get_save_data() -> Dictionary:
	return {}

func load_save_data(save_data: Dictionary) -> void:
	if save_data.is_empty():
		return
	attach()

func draw_visuals(canvas: RangeIndicator) -> void:
	super.draw_visuals(canvas)
	var report = _last_report
	if report == null and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(unit as Tower, _make_query())
	if report == null:
		return

	var margin: int = 2
	var cell_size := Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	for cell: Vector2i in report.cells.values():
		var rect: Rect2 = Rect2(Island.cell_to_position(cell) - half_size, Vector2(cell_size, cell_size))
		canvas.draw_rect(rect, canvas.highlight_color, false, 1.0)
