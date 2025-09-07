extends Node #terrain
#repository of data, purely static

enum Base { #base terrain type
	EARTH,
	RUINS,
}

class CellData:
	var terrain: Base
	var feature: Towers.Type
	var initial_state: Dictionary
	
	func _init(_terrain: Base, _feature: Towers.Type, _initial_state: Dictionary = {}):
		terrain = _terrain
		feature = _feature
		initial_state = _initial_state

class BaseStat: #defines stats for a terraintype
	var color: Color #default base color
	var navigable: bool #unaltered, is this terrain navigable
	var constructable: bool #unaltered, is this terrain constructable upon.
	
	func _init(_color: Color, _navigable: bool, _constructable: bool):
		color = _color
		navigable = _navigable
		constructable = _constructable
	
var terrain_base_stats: Dictionary[Base, BaseStat]= {
	Base.EARTH : BaseStat.new(
		Color(0.2, 0.2, 0.2, 0.2),
		true, true
	),
	Base.RUINS : BaseStat.new(
		Color.WEB_GRAY,
		true, true
	)
}

func get_color(terrain_base: Base) -> Color:
	var color: Color

	color = terrain_base_stats[terrain_base].color

	return color

func is_navigable(terrain_base: Base) -> bool: #can this terrain be navigated upon?
	return terrain_base_stats[terrain_base].navigable

func is_constructable(terrain_base: Base) -> bool: #can this terrain be constructed upon?
	return terrain_base_stats[terrain_base].constructable
