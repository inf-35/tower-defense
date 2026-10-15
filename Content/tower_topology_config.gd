extends Resource
class_name TowerTopologyConfig

@export var query_kind: TowerTopologyService.QueryKind = TowerTopologyService.QueryKind.CARDINAL_RING ##shape used to select cells around the source tower
@export_range(0, 64, 1) var min_range: int = 1 ##nearest included topology step from the source footprint
@export_range(0, 64, 1) var max_range: int = 1 ##furthest included topology step from the source footprint
@export_flags("Up", "Right", "Down", "Left") var axis_mask: int = TowerTopologyService.ALL_DIRECTIONS ##world- or facing-relative directions included by directional query kinds
@export var offsets: Array[Vector2i] = [] ##explicit local offsets used by offset-mask queries
@export var axis_space: TowerTopologyService.AxisSpace = TowerTopologyService.AxisSpace.WORLD ##whether directional axes remain world-aligned or rotate with the source tower

func build_query() -> TowerTopologyService.Query: ##creates the runtime query consumed by the island topology service
	return TowerTopologyService.Query.new(
		query_kind,
		min_range,
		max_range,
		axis_mask,
		offsets,
		axis_space
	)
