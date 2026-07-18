class_name EnvironmentProfile
extends Resource

@export var display_name: String = "" ##editor-facing label for the environment profile
@export var open_water_base: int = Terrain.Base.WATER ##revealed lake terrain for this environment
@export var open_water_label: String = "Water" ##player-facing label for the revealed open-water terrain in this environment
@export_range(0.0, 1.0, 0.001) var lake_threshold: float = 0.68 ##lower values create larger lake fields for this environment
@export_range(0.01, 10.0, 0.01) var lake_noise_frequency_multiplier: float = 1.0 ##higher values make lake blobs smaller and more frequent by increasing the main noise frequency
@export var clear_color: Color = Color(0.992, 0.937, 0.847, 1.0) ##main renderer clear color
@export var ui_canvas_color: Color = Color(0.992, 0.937, 0.847, 1.0) ##base screen tint used behind the island
@export var paper_background_color: Color = Color(1.0, 0.976, 0.941, 1.0) ##paper tint used by the terrain renderer background
@export var lake_preview_outline_color: Color = Color(0.109, 0.239, 0.31, 0.192) ##outline tint for hidden-lake previews
@export var lake_preview_fill_color: Color = Color(0.252, 0.551, 0.68, 0.024) ##fill tint for hidden-lake previews
@export var terrain_base_overrides: Dictionary[int, TerrainBaseStat] = {} ##full terrain stat overrides keyed by terrain base id
@export var placement_count_multipliers: Dictionary[int, float] = {} ##per-feature count scalars keyed by tower type
@export var forest_texture: Texture2D ##forest canopy art for this environment
@export var forest_shadow_texture: Texture2D ##forest shadow art for this environment
@export var forest_shadow_position: Vector2 = Vector2.ZERO ##forest shadow offset tuned per environment
@export var forest_shadow_scale: Vector2 = Vector2.ONE ##forest shadow scale tuned per environment

func get_open_water_base() -> Terrain.Base: ##keeps resource authroring int-based while callers stay enum-based
	return int(open_water_base) as Terrain.Base

func get_terrain_base_override(terrain_base: Terrain.Base) -> TerrainBaseStat: ##returns an override stat block when the environment reskins a terrain family
	return terrain_base_overrides.get(int(terrain_base), null)

func get_placement_count_multiplier(tower_type: Towers.Type) -> float: ##lets generation code scale specific feature families without new hardcoded branches
	return float(placement_count_multipliers.get(int(tower_type), 1.0))
