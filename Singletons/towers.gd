extends Node #Towers
#repository of towers, and their associated info

class TowerStat: #data container for stats
	var element: Element
	var construct: int = 0 #minimum terrain level to construct
	var tower_scene: PackedScene
	var flux_cost: float = 0.0
	
	func _init(_tower_scene: PackedScene, _element: Element, _construct: int = 0, _flux_cost: float = 0.0):
		tower_scene = _tower_scene
		element = _element
		construct = _construct
		flux_cost = _flux_cost

enum Type {
	VOID, #custom type for tower destruction
	PLAYER_CORE,
	TURRET,
	FROST_TOWER,
	CANNON,
	BLUEPRINT_HARVESTER,
	PALISADE,
	CATALYST
}

enum Element {
	KINETIC,
	FROST,
	FIRE,
	NATURE,
	SPARK,
	ARCANE,
	NEUTRAL,
}

static var tower_stats: Dictionary[Type, TowerStat] = {
	Type.PLAYER_CORE: TowerStat.new(
		preload("res://Units/Towers/player_core/player_core.tscn"),
		Element.ARCANE,
		20,
		0.0,
	),
	Type.TURRET: TowerStat.new(
		preload("res://Units/Towers/turret/turret.tscn"),
		Element.KINETIC,
		2,
		5.0
	),
	Type.FROST_TOWER: TowerStat.new(
		preload("res://Units/Towers/frost_tower/frost_tower.tscn"),
		Element.FROST,
		2,
		10.0,
	),
	Type.CANNON: TowerStat.new(
		preload("res://Units/Towers/cannon/cannon.tscn"),
		Element.KINETIC,
		2,
		10.0,
	),
	Type.BLUEPRINT_HARVESTER: TowerStat.new(
		preload("res://Units/Towers/blueprint_harvester/blueprint_harvester.tscn"),
		Element.ARCANE,
		2,
		8.0,
	),
	Type.PALISADE: TowerStat.new(
		preload("res://Units/Towers/palisade/palisade.tscn"),
		Element.NEUTRAL,
		1,
		1.5
	),
	Type.CATALYST: TowerStat.new(
		preload("res://Units/Towers/catalyst/catalyst.tscn"),
		Element.ARCANE,
		2,
		1.0, #TODO: make sure you change this to 10.0
	)
}

var tower_prototypes: Dictionary[Type, Tower] = {} #prototypical towers created and stored as reference

func get_tower_stat(tower_type: Type, attr: Attributes.id): #gets a tower's stat based off an unmodified prototype
	if not tower_prototypes.has(tower_type): #if no prototype
		tower_prototypes[tower_type] = create_tower(tower_type) #create prototypical tower
	
	var prototype: Tower = tower_prototypes[tower_type]

	var value = prototype.get_stat(attr)
	if not value: #i.e. null
		return 0.0
	return prototype.get_stat(attr)

static func get_tower_element(tower_type: Type) -> Towers.Element:
	return tower_stats[tower_type].element

static func get_tower_scene(tower_type: Type) -> PackedScene:
	return tower_stats[tower_type].tower_scene

static func create_tower(tower_type: Type) -> Tower:
	return get_tower_scene(tower_type).instantiate()
