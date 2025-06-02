class_name Towers
#repository of towers, and their associated info

class TowerStat: #data container for stats
	var construct: int = 0 #minimum terrain level to construct
	var tower_scene: PackedScene
	
	func _init(_tower_scene: PackedScene, _construct: int = 0):
		tower_scene = _tower_scene
		construct = _construct
		

enum Type {
	PLAYER_CORE,
	DPS_TOWER,
	SLOW_TOWER,
	PALISADE
}

static var tower_stats : Dictionary[Type, TowerStat] = {
	Type.PLAYER_CORE: TowerStat.new(
		preload("res://Units/Towers/player_core.tscn"),
		20,
	),
	Type.DPS_TOWER: TowerStat.new(
		preload("res://Units/Towers/player_core.tscn"),
		3,
	),
	Type.SLOW_TOWER: TowerStat.new(
		preload("res://Units/Towers/player_core.tscn"),
		2,
	),
	Type.PALISADE: TowerStat.new(
		preload("res://Units/Towers/player_core.tscn"),
		1,
	),
}

static func get_tower_scene(tower: Type) -> PackedScene:
	match tower:
		Type.PLAYER_CORE:
			return preload("res://Units/Towers/player_core.tscn")
		Type.DPS_TOWER:
			return preload("res://Units/Towers/basic_tower.tscn")
		Type.SLOW_TOWER:
			return preload("res://Units/Towers/slow_tower.tscn")
		Type.PALISADE:
			return preload("res://Units/Towers/palisade.tscn")
		_:
			return
