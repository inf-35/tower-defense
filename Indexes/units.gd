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
	BASIC_UNIT
}

static var unit_stats : Dictionary[Type, UnitStat] = {
	Type.BASIC_UNIT: UnitStat.new(
		preload("res://Units/Enemies/basic_unit.tscn"),
		0.5,
		1.0
	)
}

static func get_unit_flux(unit: Type) -> float:
	return unit_stats[unit].flux_value

static func get_unit_scene(unit: Type) -> PackedScene:
	return unit_stats[unit].unit_scene

static func create_unit(unit: Type) -> Unit:
	return get_unit_scene(unit).instantiate()
