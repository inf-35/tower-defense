extends Node2D
class_name ShadowComponent

const SILHOUETTE_SHADER := preload("res://Shaders/silhouette.gdshader")
const SWEPT_SHADOW_SHADER: Shader = preload("res://Shaders/swept_shadow.gdshader")
const HEIGHT_SHADOW_COLOR: Color = Color(0.316, 0.265, 0.193, 1.0)

#defines "height": multiplies the global offset.
#1.0 = standard, 0.5 = short box, 3.0 = tall tower
@export var height_multiplier: float = 1.0
@export_range(2, 32, 1) var shadow_samples: int = 8 ##alpha samples between the building footprint and shadow tip; higher counts smooth long thin shadows

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
var _sweep_offset: Vector2 = Vector2.ZERO
var _height_offset: Vector2 = Vector2.ZERO
var _last_source_rect: Rect2
var _last_frame_region: Rect2
var _last_texture_size: Vector2 = Vector2.ZERO
var _last_sweep_offset: Vector2 = Vector2.INF
var _last_height_offset: Vector2 = Vector2.INF
var _last_frame_flip: Vector2 = Vector2.ZERO
var _last_sample_count: int = 0
static var _shared_shadow_material: ShaderMaterial
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

	add_to_group(DebugAssistant.GROUP_SHADOW_COMPONENTS)

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
	shadow_material = _get_shared_shadow_material()
	shadow_sprite.material = shadow_material

	height_material = _get_shared_height_material()
	height_sprite.material = height_material

	#4. connect to sun changes
	Sun.sun_changed.connect(_update_appearance)

	#5. initial update
	_update_appearance()
	_sync_texture_data()

func _process(_delta: float) -> void: ##keeps dynamic shadows matched to animated parent sprites
	#only run every frame if the object animates (moves, walks, changes frame)
	if is_dynamic and parent_sprite:
		_sync_texture_data()

static func _get_shared_shadow_material() -> ShaderMaterial: ##returns the shared global shadow material so static shadows batch more easily
	if not is_instance_valid(_shared_shadow_material):
		_shared_shadow_material = ShaderMaterial.new()
		_shared_shadow_material.shader = SWEPT_SHADOW_SHADER
	return _shared_shadow_material

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
	if source_rect == _last_source_rect and frame_region == _last_frame_region and texture_size == _last_texture_size and _sweep_offset == _last_sweep_offset and _height_offset == _last_height_offset and frame_flip == _last_frame_flip and shadow_samples == _last_sample_count:
		return
	_last_source_rect = source_rect
	_last_frame_region = frame_region
	_last_texture_size = texture_size
	_last_sweep_offset = _sweep_offset
	_last_height_offset = _height_offset
	_last_frame_flip = frame_flip
	_last_sample_count = shadow_samples
	shadow_sprite.position = source_rect.position + _height_offset + _sweep_offset.min(Vector2.ZERO)
	shadow_sprite.scale = (frame_size + _sweep_offset.abs()) / frame_size
	shadow_sprite.set_instance_shader_parameter(&"frame_size", frame_size)
	shadow_sprite.set_instance_shader_parameter(&"sweep_offset", _sweep_offset)
	shadow_sprite.set_instance_shader_parameter(&"frame_region", Vector4(frame_region.position.x / texture_size.x, frame_region.position.y / texture_size.y, frame_size.x / texture_size.x, frame_size.y / texture_size.y))
	shadow_sprite.set_instance_shader_parameter(&"frame_flip", frame_flip)
	shadow_sprite.set_instance_shader_parameter(&"sample_count", shadow_samples)

func _update_appearance() -> void: ##updates shadow color and offset when the shared sun direction changes
	#update shader color
	shadow_material.set_shader_parameter("shadow_color", Sun.shadow_color)
	height_material.set_shader_parameter("shadow_color", HEIGHT_SHADOW_COLOR)
	#update position offset (the "height" logic)
	#the shadow is a child of the parent, so position is local relative to parent
	_sweep_offset = (Sun.global_offset * height_multiplier).rotated(-parent_sprite.global_rotation)
	_height_offset = (Vector2(0, Sun.global_offset.y) * 0.4 * height_multiplier).rotated(-parent_sprite.global_rotation)
	height_sprite.position = _height_offset
	_sync_sweep_geometry()
