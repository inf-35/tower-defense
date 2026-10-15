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
@export var lake_preview_fill_color: Color = Color(0.252, 0.551, 0.68, 0.024) ##fill tint for hidden-lake previews
@export_range(0.0, 1.0, 0.01) var lake_preview_outline_strength: float = 0.34 ##relative terrain-contour opacity used around hidden water
@export_group("Paper")
@export_range(0.0, 1.0, 0.001) var paper_crumple_strength: float = 0.306 ##opacity of the broad photographed paper folds
@export_range(0.0, 0.25, 0.001) var paper_grain_strength: float = 0.0 ##opacity of the fine static parchment grain
@export_range(0.25, 4.0, 0.05) var paper_grain_scale: float = 1.0 ##screen density of the fine parchment grain
@export var paper_grain_color: Color = Color(0.34, 0.3, 0.23, 1.0) ##ink tint used by fine paper fibres and specks
@export_range(0.0, 0.25, 0.001) var paper_brush_strength: float = 0.0 ##opacity of the authored brush and fibre texture stored by the paper layer
@export_group("Route Paint")
@export var path_wash_color: Color = Color(0.98, 0.94, 0.82, 0.48) ##watercolor ground tint beneath ordinary enemy routes
@export var path_indicator_color: Color = Color(0.68, 0.52, 0.19, 0.42) ##ink tint for the animated ordinary-route marks
@export_group("World Style")
@export var world_style_enabled: bool = false ##enables the environment's pre-lighting palette and value treatment
@export_range(0.0, 1.0, 0.01) var world_style_strength: float = 1.0 ##blends continuously between authored pixels and the styled result
@export var world_tone_input: Vector3 = Vector3(0.58, 0.835, 0.902) ##sampled shadow, midtone, and highlight luminance anchors
@export var world_tone_output: Vector3 = Vector3(0.562, 0.817, 0.922) ##target luminance for the corresponding input anchors
@export_range(0.0, 2.0, 0.01) var world_neutral_chroma_scale: float = 0.86 ##reduces ordinary environmental colour while retaining its hue
@export_range(0.0, 2.0, 0.01) var world_accent_chroma_scale: float = 1.06 ##preserves or slightly lifts deliberately saturated gameplay accents
@export_range(0.0, 1.0, 0.001) var world_accent_chroma_start: float = 0.112 ##chroma where the shader begins transitioning from neutral treatment
@export_range(0.0, 1.0, 0.001) var world_accent_chroma_end: float = 0.137 ##chroma where the accent treatment is fully applied
@export_group("Night Lighting")
@export var night_ambient_color: Color = Color(0.501, 0.589, 0.91, 1.0) ##canvas-wide combat tint applied before local population-building lights
@export_range(0.01, 2.0, 0.01) var night_transition_seconds: float = 0.5 ##real-time duration of the day-to-night and night-to-day fades
@export_color_no_alpha var night_light_color: Color = Color(1.0, 0.63, 0.2, 1.0) ##environment-wide hue applied to every local combat light
@export_range(0.0, 4.0, 0.01) var night_light_energy_multiplier: float = 1.0 ##environment-wide multiplier applied to each light source before pixel-level accumulation and capping
@export_range(0.0, 1.0, 0.01) var night_max_light_energy: float = 0.42 ##hard cap on accumulated local light at any one screen pixel
@export_range(0.0, 2.0, 0.01) var night_surface_light_strength: float = 1.0 ##rate at which local light restores the underlying paper and paint values
@export_range(0.0, 1.0, 0.01) var night_surface_tint_strength: float = 0.7 ##amount of authored light hue mixed into restored surfaces
@export_range(0.0, 2.0, 0.01) var night_lit_chroma_scale: float = 1.0 ##luminance-preserving colour recovery applied only inside local lights
@export_range(0.0, 1.0, 0.01) var night_additive_bloom_strength: float = 0.12 ##small additive halo layered over the surface-aware light response
@export_range(0.0, 1.0, 0.01) var night_dark_pixel_response: float = 0.08 ##minimum local-light response retained by dark ink pixels
@export_range(0.1, 4.0, 0.05) var night_luminance_power: float = 0.65 ##shapes how strongly pale surfaces respond relative to dark linework
@export_range(0.0, 1.0, 0.01) var night_ui_tint_strength: float = 0.22 ##portion of the combat-night hue applied to run ui surfaces
@export_range(0.0, 4.0, 0.01) var night_projectile_chroma_multiplier: float = 0.8 ##global multiplier for exempt projectile and trail chroma during combat night
@export_range(0.0, 1.0, 0.01) var night_projectile_chroma_alpha: float = 0.1 ##base opacity of additive projectile chroma on the exempt pass
@export_range(1.0, 4.0, 0.01) var night_projectile_chroma_scale: float = 1.85 ##maximum scale target for projectile chroma footprints
@export_range(0.0, 2.0, 0.01) var night_projectile_chroma_boost: float = 0.75 ##saturation lift applied before projectile chroma is drawn
@export_range(0.0, 1.0, 0.01) var night_projectile_shading_fraction: float = 0.35 ##fraction of combat-night ambient reapplied to otherwise exempt projectile visuals
@export_group("Terrain Paint")
@export_range(0.0, 0.5, 0.01) var terrain_cut_threshold: float = 0.2 ##pure-wash depth inside the island edge; higher values leave a wider pale, watery margin before solid pigment appears
@export_range(0.0, 2.0, 0.01) var terrain_edge_softness: float = 1.0 ##distance over which wash becomes body pigment; higher values feel diffuse and cloudlike, lower values feel crisp and inked
@export_range(0.1, 5.0, 0.01) var terrain_center_falloff: float = 2.0 ##curve of the wash-to-pigment buildup; higher values hold pale wash longer before pigment gathers sharply toward the interior
@export_range(0.0, 1.0, 0.01) var terrain_brush_strength: float = 0.3 ##amount of stamped-mask breakup exposing pale wash; higher values feel drier, patchier, and more visibly hand-brushed
@export_range(0.0, 1.0, 0.01) var terrain_min_paint_coverage: float = 0.5 ##floor retained in sparse brush-mask regions; higher values fill holes and make paint feel denser and more continuous
@export_range(0.0, 1.0, 0.01) var terrain_color_strength: float = 1.0 ##body-color influence over the local wash; higher values produce clearer terrain identities and stronger saturation
@export_range(0.0, 1.0, 0.01) var terrain_transition_softness: float = 0.15 ##width of handoff between neighboring terrain families; higher values blend broadly while lower values preserve tile-like color boundaries
@export_range(0.0, 12.0, 0.1) var terrain_warp_strength: float = 8.0 ##world-space wobble of terrain-family ownership; higher values make borders meander and bleed like uneven wet paint
@export_range(0.0, 1.0, 0.01) var terrain_posterization_strength: float = 0.5 ##blend from continuous pigment buildup to stepped pigment-density regions
@export_range(2, 32, 1) var terrain_posterization_levels: int = 4 ##number of pigment-density bands; lower values make broader, more graphic watercolor pools
@export var terrain_coastline_color: Color = Color(0.3, 0.28, 0.22, 1.0) ##ink color around the island silhouette; dark neutrals resemble pencil while saturated colors feel outlined or illustrated
@export_range(0.0, 1.0, 0.01) var terrain_coastline_strength: float = 0.0 ##visibility of the outer contour; higher values make the island read as a firmly drawn shape instead of a loose wash
@export_range(0.01, 1.0, 0.01) var terrain_coastline_width: float = 0.2 ##half-width of the outer contour in terrain-distance units; larger values feel marker-like rather than pencil-thin
@export_range(0.0, 1.0, 0.01) var terrain_waterline_strength: float = 0.0 ##visibility of contours between waterlike and neighboring terrain; higher values separate lakes more decisively from land
@export_range(0.005, 0.25, 0.005) var terrain_waterline_width: float = 0.03 ##half-width of water contours in dominance units; larger values create broader shoreline bands
@export_range(-1.0, 0.5, 0.001) var terrain_waterline_level: float = -1.0 ##dominance value traced by the shoreline; negative derives it from open water while higher values pull the line toward stronger water ownership
@export_group("")
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
