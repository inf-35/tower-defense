extends Node #terrain
#repository of data, purely static

enum Base { #base terrain type
	EARTH,
	SETTLEMENT,
	HIGHLAND,
	WATER,
	ICE,
}
class CellData: #used to communicate info during runtime
	var terrain: Base
	var feature: Towers.Type
	var initial_state: Dictionary

	func _init(_terrain: Base, _feature: Towers.Type, _initial_state: Dictionary = {}) -> void:
		terrain = _terrain
		feature = _feature
		initial_state = _initial_state

#terrain database, as a global class, is in a nother script (Objects/Indexes/terrain_database.gd)

var terrain_database: TerrainDatabase = preload("res://Indexes/default_terrain.tres")

func get_base_stat(terrain_base: Base, environment: Run.GameEnvironment = Run.current_game_environment) -> TerrainBaseStat: ##returns the active terrain stat block after environment reskins are applied
	var profile: EnvironmentProfile = Run.get_environment_profile(environment)
	if profile != null:
		var override_stat: TerrainBaseStat = profile.get_terrain_base_override(terrain_base)
		if override_stat != null:
			return override_stat
	return terrain_database.terrain_base_types[terrain_base]

func get_color(terrain_base: Base) -> Color:
	return get_base_stat(terrain_base).color

func get_wash_color(terrain_base: Base) -> Color:
	return get_base_stat(terrain_base).wash_color

func get_dominance_strength(terrain_base: Base) -> float:
	return get_base_stat(terrain_base).dominance_strength

func get_icon(terrain_base: Base) -> Texture2D:
	return get_base_stat(terrain_base).texture

func is_navigable(terrain_base: Base) -> bool: #can this terrain be navigated upon?
	return get_base_stat(terrain_base).navigable

func is_constructable(terrain_base: Base) -> bool: #can this terrain be constructed upon?
	return get_base_stat(terrain_base).constructable

func get_modifiers_for_base(terrain_base: Base) -> Array[ModifierDataPrototype]:
	return get_base_stat(terrain_base).modifiers

func get_open_water_base(environment: Run.GameEnvironment = Run.current_game_environment) -> Base: ##returns the revealed lake terrain for the active environment
	var profile: EnvironmentProfile = Run.get_environment_profile(environment)
	if profile != null:
		return profile.get_open_water_base()
	return Base.WATER

func get_open_water_label(environment: Run.GameEnvironment = Run.current_game_environment) -> String: ##returns the player-facing label for open water in the active environment
	var profile: EnvironmentProfile = Run.get_environment_profile(environment)
	if profile != null:
		return profile.open_water_label
	return "Water"

func is_waterlike(terrain_base: Base) -> bool: ##treats woods water and winter ice as the same gameplay family for generic checks
	return terrain_base == Base.WATER or terrain_base == Base.ICE

func matches_reference_terrain(actual_terrain: Base, reference_terrain: Base) -> bool: ##lets authored water checks continue to match ice without duplicating content resources
	if actual_terrain == reference_terrain:
		return true
	if is_waterlike(actual_terrain) and is_waterlike(reference_terrain):
		return true
	return false
