extends Node #terrain
#repository of data, purely static

enum Base { #base terrain type
	EARTH,
	SETTLEMENT,
	HIGHLAND,
}
class CellData: #used to communicate info during runtime
	var terrain: Base
	var feature: Towers.Type
	var initial_state: Dictionary
	
	func _init(_terrain: Base, _feature: Towers.Type, _initial_state: Dictionary = {}):
		terrain = _terrain
		feature = _feature
		initial_state = _initial_state
		
#terrain database, as a global class, is in a nother script (Objects/Indexes/terrain_database.gd)

var terrain_database: TerrainDatabase = preload("res://Indexes/default_terrain.tres")

func get_color(terrain_base: Base) -> Color:
	var color: Color

	color = terrain_database.terrain_base_types[terrain_base].color

	return color

func get_icon(terrain_base: Base) -> Texture2D:
	return terrain_database.terrain_base_types[terrain_base].texture

func is_navigable(terrain_base: Base) -> bool: #can this terrain be navigated upon?
	return terrain_database.terrain_base_types[terrain_base].navigable

func is_constructable(terrain_base: Base) -> bool: #can this terrain be constructed upon?
	return terrain_database.terrain_base_types[terrain_base].constructable
	
func get_modifiers_for_base(terrain_base: Base) -> Array[ModifierDataPrototype]:
	return terrain_database.terrain_base_types[terrain_base].modifiers
