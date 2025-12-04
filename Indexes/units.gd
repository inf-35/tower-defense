class_name Units
#repository of towers, and their associated info

class UnitStat: #data container for stats
	var unit_scene: PackedScene
	var flux_value: float #how much flux this unit nets the player when killed
	var strength_value: float #how "strong" this unit is, used for score and targeting
	
	func _init(_unit_scene, _flux_value, _strength_value):
		unit_scene = _unit_scene
		flux_value = _flux_value
		strength_value = _strength_value

enum Type {
	BASIC,
	BUFF,
	DRIFTER,
	ARCHER,
	TROLL,
	WARRIOR,
	HEALER,
}

static var unit_stats : Dictionary[Type, UnitStat] = {
	Type.BASIC: UnitStat.new(
		preload("res://Units/Enemies/basic_unit/basic_unit.tscn"),
		0.5,
		1.0
	),
	Type.BUFF: UnitStat.new(
		preload("res://Units/Enemies/buff_unit/buff_unit.tscn"),
		0.8,
		2.0,
	),
	Type.DRIFTER: UnitStat.new(
		preload("res://Units/Enemies/drifter/drifter.tscn"),
		0.8,
		1.5,
	),
	Type.ARCHER: UnitStat.new(
		preload("res://Units/Enemies/archer/archer.tscn"),
		0.8,
		2.5,
	),
	Type.TROLL: UnitStat.new(
		preload("res://Units/Enemies/troll/troll.tscn"),
		1.5,
		4.0
	),
	Type.WARRIOR: UnitStat.new(
		preload("res://Units/Enemies/warrior/warrior.tscn"),
		0.8,
		1.5,
	),
	Type.HEALER: UnitStat.new(
		preload("res://Units/Enemies/healer/healer.tscn"),
		1.2,
		2.0,
	)
}

static func get_unit_flux(unit: Type) -> float:
	return unit_stats[unit].flux_value

static func get_unit_scene(unit: Type) -> PackedScene:
	return unit_stats[unit].unit_scene

static func create_unit(unit: Type) -> Unit:
	var _unit: Unit = get_unit_scene(unit).instantiate()
	_unit.flux_value = get_unit_flux(unit)
	return _unit
