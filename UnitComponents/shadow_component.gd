extends Node2D
class_name ShadowComponent

const SILHOUETTE_SHADER := preload("res://Shaders/silhouette.gdshader")

#defines "height": multiplies the global offset.
#1.0 = standard, 0.5 = short box, 3.0 = tall tower
@export var height_multiplier: float = 1.0

#uncheck this for static buildings to save performance
@export var is_dynamic: bool = false

var shadow_sprite: Sprite2D
var height_sprite: Sprite2D
var parent_sprite: Sprite2D
var shadow_material: ShaderMaterial
var height_material: ShaderMaterial

func _ready() -> void:
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
		return

	add_to_group(DebugAssistant.GROUP_SHADOW_COMPONENTS)

	#2. create the shadow sprite
	shadow_sprite = Sprite2D.new()
	#draw behind the parent
	shadow_sprite.z_index = -2
	shadow_sprite.z_as_relative = true
	add_child.call_deferred(shadow_sprite)

	height_sprite = Sprite2D.new()
	height_sprite.z_index = -1
	height_sprite.z_as_relative = true
	add_child.call_deferred(height_sprite)

	#3. apply the silhouette shader
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = SILHOUETTE_SHADER
	shadow_sprite.material = shadow_material

	height_material = ShaderMaterial.new()
	height_material.shader = SILHOUETTE_SHADER
	height_sprite.material = height_material

	#4. connect to sun changes
	Sun.sun_changed.connect(_update_appearance)

	#5. initial update
	_update_appearance()
	_sync_texture_data()

func _process(_delta) -> void:
	#only run every frame if the object animates (moves, walks, changes frame)
	if is_dynamic and parent_sprite:
		_sync_texture_data()

func _sync_texture_data() -> void:
	#copy all visual properties from the parent to the shadow
	shadow_sprite.texture = parent_sprite.texture
	shadow_sprite.hframes = parent_sprite.hframes
	shadow_sprite.vframes = parent_sprite.vframes
	shadow_sprite.frame = parent_sprite.frame
	shadow_sprite.flip_h = parent_sprite.flip_h
	shadow_sprite.offset = parent_sprite.offset
	shadow_sprite.texture = parent_sprite.texture
	height_sprite.visible = true

	height_sprite.texture = parent_sprite.texture
	height_sprite.hframes = parent_sprite.hframes
	height_sprite.vframes = parent_sprite.vframes
	height_sprite.frame = parent_sprite.frame
	height_sprite.flip_h = parent_sprite.flip_h
	height_sprite.offset = parent_sprite.offset
	height_sprite.texture = parent_sprite.texture

func _update_appearance() -> void:
	#update shader color
	shadow_material.set_shader_parameter("shadow_color", Sun.shadow_color)
	height_material.set_shader_parameter("shadow_color", Color(0.412, 0.373, 0.294))
	#update position offset (the "height" logic)
	#the shadow is a child of the parent, so position is local relative to parent
	shadow_sprite.position = (Sun.global_offset * height_multiplier).rotated(-parent_sprite.global_rotation)
	height_sprite.position = (Vector2(0,Sun.global_offset.y) * 0.4 * height_multiplier).rotated(-parent_sprite.global_rotation)
