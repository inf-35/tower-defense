extends Node2D
class_name ShadowComponent

const SILHOUETTE_SHADER := preload("res://Shaders/silhouette.gdshader")
const SWEPT_SHADOW_SHADER: Shader = preload("res://Shaders/swept_shadow.gdshader")
const HEIGHT_SHADOW_COLOR: Color = Color(0.316, 0.265, 0.193, 1.0)

#defines "height": multiplies the global offset.
#1.0 = standard, 0.5 = short box, 3.0 = tall tower
@export var height_multiplier: float = 1.0
@export_range(2, 32, 1) var shadow_samples: int = 8 ##alpha samples between the building footprint and shadow tip; higher counts smooth long thin shadows

@export_group("Night Projection")
@export_range(0.0, 40.0, 0.5) var night_light_vertical_offset: float = 15.0 ##upward visual offset applied to local lights so their own towers still cast a downward shadow
@export_range(0.0, 40.0, 0.5) var night_min_shadow_length: float = 10.0 ##minimum projected length for an object positioned directly beneath its nearest light
@export_range(0.0, 1.0, 0.01) var night_distance_length_scale: float = 2.0 ##additional shadow pixels gained per world pixel of distance from the nearest light
@export_range(1.0, 128.0, 1.0) var night_max_shadow_length: float = 60.0 ##caps the base distant projection before tower height scales it further
@export_range(0.0, 1.0, 0.01) var night_min_alpha_multiplier: float = 0.05 ##faintest ground-shadow opacity retained once the caster reaches the fade distance
@export_range(1.0, 500.0, 1.0) var night_alpha_fade_distance: float = 50.0 ##world-space distance over which ground shadows fade from full opacity to the minimum
@export_group("")

#uncheck this for static buildings to save performance
@export var is_dynamic: bool = false:
	set(value):
		is_dynamic = value
		set_process(is_dynamic)

var shadow_sprite: Sprite2D
var height_sprite: Sprite2D
var parent_sprite: Sprite2D
var shadow_material: ShaderMaterial
var height_material: ShaderMaterial
var _lighting_service: CombatLightingService
var _day_sweep_offset: Vector2 = Vector2.ZERO
var _sweep_offset: Vector2 = Vector2.ZERO
var _secondary_sweep_offset: Vector2 = Vector2.ZERO
var _height_offset: Vector2 = Vector2.ZERO
var _last_source_rect: Rect2
var _last_frame_region: Rect2
var _last_texture_size: Vector2 = Vector2.ZERO
var _last_day_sweep_offset: Vector2 = Vector2.INF
var _last_sweep_offset: Vector2 = Vector2.INF
var _last_secondary_sweep_offset: Vector2 = Vector2.INF
var _last_height_offset: Vector2 = Vector2.INF
var _last_frame_flip: Vector2 = Vector2.ZERO
var _last_sample_count: int = 0
var _night_secondary_enabled: bool = false
var _night_alpha_multipliers: Vector2 = Vector2.ZERO
var _night_mix: float = 0.0
var _last_night_secondary_enabled: bool = false
var _last_projection_mode: int = -1
static var _shared_height_material: ShaderMaterial

func _ready() -> void: ##builds the shadow sprites once, then only keeps processing enabled for authored dynamic shadows
	set_process(is_dynamic)
	#1. find the parent sprite to copy
	var parent = get_parent()
	await parent.ready
	if parent is Sprite2D:
		parent_sprite = parent
	elif parent is Node2D:
		#try to find a sprite child if the parent is just a container
		#adjust 'sprite2d' to whatever your main visual node is named
		parent_sprite = parent.get_node("Sprite2D")

	if not parent_sprite:
		push_warning("ShadowCaster: No parent Sprite2D found!")
		return

	if DebugAssistant.disable_shadows:
		set_process(false)
		return

	#2. create the shadow sprite
	shadow_sprite = Sprite2D.new()
	#draw behind the parent
	shadow_sprite.z_index = -2
	shadow_sprite.z_as_relative = true
	shadow_sprite.centered = false
	add_child.call_deferred(shadow_sprite)

	height_sprite = Sprite2D.new()
	height_sprite.z_index = -1
	height_sprite.z_as_relative = true
	add_child.call_deferred(height_sprite)

	#3. apply the silhouette shader
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = SWEPT_SHADOW_SHADER
	shadow_sprite.material = shadow_material

	height_material = _get_shared_height_material()
	height_sprite.material = height_material

	add_to_group(DebugAssistant.GROUP_SHADOW_COMPONENTS)

	#4. connect to sun changes
	Sun.sun_changed.connect(_update_appearance)

	#5. initial update
	_update_appearance()
	_sync_texture_data()
	var island_owner: Node = parent
	while island_owner != null and not (island_owner is Island):
		island_owner = island_owner.get_parent()
	if island_owner is Island:
		_lighting_service = (island_owner as Island).combat_lighting_service
	if is_instance_valid(_lighting_service):
		_lighting_service.register_shadow(self)

func _exit_tree() -> void:
	if is_instance_valid(_lighting_service):
		_lighting_service.unregister_shadow(self)

func _process(_delta: float) -> void: ##keeps dynamic shadows matched to animated parent sprites
	#only run every frame if the object animates (moves, walks, changes frame)
	if is_dynamic and parent_sprite:
		_sync_texture_data()

static func _get_shared_height_material() -> ShaderMaterial: ##returns the shared height material for the constant faux-height silhouette layer
	if not is_instance_valid(_shared_height_material):
		_shared_height_material = ShaderMaterial.new()
		_shared_height_material.shader = SILHOUETTE_SHADER
		_shared_height_material.set_shader_parameter("shadow_color", HEIGHT_SHADOW_COLOR)
	return _shared_height_material

func _sync_texture_data() -> void: ##copies source frames while the ground shadow uses an expanded quad and shader-side flips
	#copy all visual properties from the parent to the shadow
	shadow_sprite.texture = parent_sprite.texture
	shadow_sprite.hframes = parent_sprite.hframes
	shadow_sprite.vframes = parent_sprite.vframes
	shadow_sprite.frame = parent_sprite.frame
	shadow_sprite.region_enabled = parent_sprite.region_enabled
	shadow_sprite.region_rect = parent_sprite.region_rect
	height_sprite.visible = true

	height_sprite.texture = parent_sprite.texture
	height_sprite.hframes = parent_sprite.hframes
	height_sprite.vframes = parent_sprite.vframes
	height_sprite.frame = parent_sprite.frame
	height_sprite.flip_h = parent_sprite.flip_h
	height_sprite.flip_v = parent_sprite.flip_v
	height_sprite.centered = parent_sprite.centered
	height_sprite.region_enabled = parent_sprite.region_enabled
	height_sprite.region_rect = parent_sprite.region_rect
	height_sprite.offset = parent_sprite.offset
	_sync_sweep_geometry()

func _sync_sweep_geometry() -> void: ##expands real sprite bounds to include the whole sweep so culling agrees with the shader
	if parent_sprite.texture == null:
		return
	var source_rect: Rect2 = parent_sprite.get_rect()
	var frame_size: Vector2 = source_rect.size
	if frame_size.x <= 0.0 or frame_size.y <= 0.0:
		return
	var texture_size: Vector2 = parent_sprite.texture.get_size()
	var source_region: Rect2 = parent_sprite.region_rect if parent_sprite.region_enabled else Rect2(Vector2.ZERO, texture_size)
	var frame_region := Rect2(source_region.position + Vector2(parent_sprite.frame_coords) * frame_size, frame_size)
	var frame_flip := Vector2(float(parent_sprite.flip_h), float(parent_sprite.flip_v))
	var projection_mode: int = 1
	if is_zero_approx(_night_mix):
		projection_mode = 0
	elif is_equal_approx(_night_mix, 1.0):
		projection_mode = 2
	if source_rect == _last_source_rect and frame_region == _last_frame_region and texture_size == _last_texture_size and _day_sweep_offset == _last_day_sweep_offset and _sweep_offset == _last_sweep_offset and _secondary_sweep_offset == _last_secondary_sweep_offset and _height_offset == _last_height_offset and frame_flip == _last_frame_flip and shadow_samples == _last_sample_count and _night_secondary_enabled == _last_night_secondary_enabled and projection_mode == _last_projection_mode:
		return
	_last_source_rect = source_rect
	_last_frame_region = frame_region
	_last_texture_size = texture_size
	_last_day_sweep_offset = _day_sweep_offset
	_last_sweep_offset = _sweep_offset
	_last_secondary_sweep_offset = _secondary_sweep_offset
	_last_height_offset = _height_offset
	_last_frame_flip = frame_flip
	_last_sample_count = shadow_samples
	_last_night_secondary_enabled = _night_secondary_enabled
	_last_projection_mode = projection_mode
	var normalized_frame_region := Vector4(frame_region.position.x / texture_size.x, frame_region.position.y / texture_size.y, frame_size.x / texture_size.x, frame_size.y / texture_size.y)
	var minimum_offset: Vector2 = Vector2.ZERO
	var maximum_offset: Vector2 = Vector2.ZERO
	if projection_mode < 2:
		minimum_offset = minimum_offset.min(_day_sweep_offset)
		maximum_offset = maximum_offset.max(_day_sweep_offset)
	if projection_mode > 0:
		minimum_offset = minimum_offset.min(_sweep_offset)
		maximum_offset = maximum_offset.max(_sweep_offset)
		if _night_secondary_enabled:
			minimum_offset = minimum_offset.min(_secondary_sweep_offset)
			maximum_offset = maximum_offset.max(_secondary_sweep_offset)
	var expanded_size: Vector2 = frame_size + maximum_offset - minimum_offset
	shadow_sprite.position = source_rect.position + _height_offset + minimum_offset
	shadow_sprite.scale = expanded_size / frame_size
	shadow_material.set_shader_parameter(&"frame_size", frame_size)
	shadow_material.set_shader_parameter(&"frame_region", normalized_frame_region)
	shadow_material.set_shader_parameter(&"frame_flip", frame_flip)
	shadow_material.set_shader_parameter(&"sample_count", shadow_samples)
	shadow_material.set_shader_parameter(&"quad_origin", minimum_offset)
	shadow_material.set_shader_parameter(&"quad_size", expanded_size)
	shadow_material.set_shader_parameter(&"day_sweep_offset", _day_sweep_offset)
	shadow_material.set_shader_parameter(&"night_sweep_offset", _sweep_offset)
	shadow_material.set_shader_parameter(&"secondary_night_sweep_offset", _secondary_sweep_offset)
	shadow_material.set_shader_parameter(&"secondary_night_enabled", _night_secondary_enabled)

func set_night_projections(light_positions: Array[Vector2]) -> void: ##stores up to two service-selected local-light projections without owning phase state
	var caster_position: Vector2 = parent_sprite.global_position
	var minimum_length: float = minf(night_min_shadow_length, night_max_shadow_length)
	var maximum_length: float = maxf(night_min_shadow_length, night_max_shadow_length)
	_height_offset = (Vector2(0, Sun.global_offset.y) * 0.4 * height_multiplier).rotated(-parent_sprite.global_rotation)
	var projection_count: int = mini(light_positions.size(), 2)
	_night_secondary_enabled = projection_count > 1
	_sweep_offset = Vector2.ZERO
	_secondary_sweep_offset = Vector2.ZERO
	_night_alpha_multipliers = Vector2.ZERO

	for index: int in range(projection_count):
		var light_position: Vector2 = light_positions[index]
		var apparent_light_position: Vector2 = light_position + Vector2.UP * night_light_vertical_offset
		var away_from_light: Vector2 = caster_position - apparent_light_position
		if away_from_light.is_zero_approx():
			away_from_light = Vector2.DOWN
		var light_distance: float = caster_position.distance_to(light_position)
		var base_shadow_length: float = clampf(
			minimum_length + light_distance * night_distance_length_scale,
			minimum_length,
			maximum_length
		)
		var base_night_offset: Vector2 = away_from_light.normalized() * base_shadow_length
		var local_sweep_offset: Vector2 = (base_night_offset * height_multiplier).rotated(-parent_sprite.global_rotation)
		var fade_progress: float = clampf(light_distance / maxf(night_alpha_fade_distance, 0.001), 0.0, 1.0)
		var alpha_multiplier: float = lerpf(1.0, clampf(night_min_alpha_multiplier, 0.0, 1.0), fade_progress)
		if index == 0:
			_sweep_offset = local_sweep_offset
			_night_alpha_multipliers.x = alpha_multiplier
		else:
			_secondary_sweep_offset = local_sweep_offset
			_night_alpha_multipliers.y = alpha_multiplier

	shadow_material.set_shader_parameter(&"night_alpha_multipliers", _night_alpha_multipliers)
	height_sprite.position = _height_offset
	_sync_sweep_geometry()

func set_night_mix(night_mix: float) -> void: ##applies the service-owned day/night blend and only rebuilds bounds at endpoint crossings
	_night_mix = clampf(night_mix, 0.0, 1.0)
	shadow_material.set_shader_parameter(&"night_mix", _night_mix)
	_sync_sweep_geometry()

func _update_appearance() -> void: ##updates shared shadow colors and reapplies the sun projection when daytime owns direction
	shadow_material.set_shader_parameter("shadow_color", Sun.shadow_color)
	height_material.set_shader_parameter("shadow_color", HEIGHT_SHADOW_COLOR)
	_update_day_projection_geometry()

func _update_day_projection_geometry() -> void: ##keeps the dedicated sun projection ready without disturbing current day/night visibility
	#the shadow is a child of the parent, so world-space sun direction must become parent-local
	_day_sweep_offset = (Sun.global_offset * height_multiplier).rotated(-parent_sprite.global_rotation)
	_height_offset = (Vector2(0, Sun.global_offset.y) * 0.4 * height_multiplier).rotated(-parent_sprite.global_rotation)
	height_sprite.position = _height_offset
	_sync_sweep_geometry()
