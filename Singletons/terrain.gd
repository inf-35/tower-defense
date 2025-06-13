extends Node #terrain
#repository of data, purely static

enum Level {
	SEA, #all terrains unbuildable, with little exception
	SHORE, #buildable only to large structures
	EARTH #buildable in general
}
enum Base { #base terrain type
	EARTH,
	RUINS,
}

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
		Color.DARK_OLIVE_GREEN,
		true, true
	),
	Base.RUINS : BaseStat.new(
		Color.WEB_GRAY,
		true, true
	)
}

func get_color(terrain_level: Level, terrain_base: Base) -> Color:
	var color: Color

	color = terrain_base_stats[terrain_base].color
	
	match terrain_level:
		Level.SEA: color = Color.CADET_BLUE
		Level.SHORE: color = color.blend(Color(Color.BISQUE , 0.25))
		Level.EARTH: color = color #preserve base color

	return color

func is_navigable(terrain_base: Base) -> bool: #can this terrain be navigated upon?
	return terrain_base_stats[terrain_base].navigable

func is_constructable(terrain_base: Base) -> bool: #can this terrain be constructed upon?
	return terrain_base_stats[terrain_base].constructable
