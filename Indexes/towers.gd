class_name Towers
#repository of towers, and their associated info

class TowerStat: #data container for stats
	var construct: int = 0 #minimum terrain level to construct
	var tower_scene: PackedScene
	var flux_cost: float = 0.0
	
	func _init(_tower_scene: PackedScene, _construct: int = 0, _flux_cost: float = 0.0):
		tower_scene = _tower_scene
		construct = _construct
		flux_cost = _flux_cost

enum Type {
	PLAYER_CORE,
	TURRET,
	FROST_TOWER,
	CANNON,
	BLUEPRINT_HARVESTER,
}

static var tower_stats : Dictionary[Type, TowerStat] = {
	Type.PLAYER_CORE: TowerStat.new(
		preload("res://Units/Towers/player_core.tscn"),
		20,
		0.0,
	),
	Type.TURRET: TowerStat.new(
		preload("res://Units/Towers/turret.tscn"),
		2,
		5.0
	),
	Type.FROST_TOWER: TowerStat.new(
		preload("res://Units/Towers/frost_tower.tscn"),
		2,
		10.0,
	),
	Type.CANNON: TowerStat.new(
		preload("res://Units/Towers/cannon.tscn"),
		2,
		10.0,
	),
	Type.BLUEPRINT_HARVESTER: TowerStat.new(
		preload("res://Units/Towers/blueprint_harvester.tscn"),
		2,
		8.0,
	)
}

static func get_tower_scene(tower: Type) -> PackedScene:
	return tower_stats[tower].tower_scene

static func create_tower(tower: Type) -> Tower:
	return get_tower_scene(tower).instantiate()
