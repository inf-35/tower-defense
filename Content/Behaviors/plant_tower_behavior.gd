extends DefaultTowerBehavior
class_name PlantTowerBehavior

const CONDITION_RANGE_INFLUENCE_KEY: StringName = &"plant_condition_range"

@export var highlight_range: int = 3 ##maximum cardinal distance shown for the plant's spatial damage condition

func draw_visuals(canvas: RangeIndicator) -> void: ##draws the normal attack range while shared introspection owns the plant-condition cells
	super.draw_visuals(canvas)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes every cell considered by the plant's intrinsic spatial damage condition
	if not is_instance_valid(unit) or not unit is Tower:
		return []
	if not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return []

	var query := TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.CARDINAL_RING,
		1,
		highlight_range,
		TowerTopologyService.ALL_DIRECTIONS,
		[],
		TowerTopologyService.AxisSpace.WORLD
	)
	var report: TowerTopologyService.Report = Run.references.island.topology_service.query(unit as Tower, query)
	return [TowerInfluence.for_cells(
		CONDITION_RANGE_INFLUENCE_KEY,
		TowerInfluence.Kind.LINK,
		_get_report_cells(report),
		null,
		[],
		false,
		TowerInfluence.Scope.WORLD
	)]
