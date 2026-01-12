extends Node2D
class_name ShadowComponent

# Defines "Height": Multiplies the global offset.
# 1.0 = Standard, 0.5 = Short box, 3.0 = Tall Tower
@export var height_multiplier: float = 1.0 

# Uncheck this for static buildings to save performance
@export var is_dynamic: bool = false 

var shadow_sprite: Sprite2D
var parent_sprite: Sprite2D
var shadow_material: ShaderMaterial

func _ready():
	# 1. Find the parent sprite to copy
	var parent = get_parent()
	await parent.ready
	if parent is Sprite2D:
		parent_sprite = parent
	elif parent is Node2D:
		# Try to find a sprite child if the parent is just a container
		# Adjust 'Sprite2D' to whatever your main visual node is named
		parent_sprite = parent.get_node("Sprite2D")
		
	if not parent_sprite:
		push_warning("ShadowCaster: No parent Sprite2D found!")
		return

	# 2. Create the Shadow Sprite
	shadow_sprite = Sprite2D.new()
	# Draw behind the parent
	shadow_sprite.z_index = -1
	shadow_sprite.z_as_relative = true
	add_child.call_deferred(shadow_sprite)
	
	# 3. Apply the Silhouette Shader
	shadow_material = ShaderMaterial.new()
	shadow_material.shader = load("res://Shaders/silhouette.gdshader") # UPDATE THIS PATH
	shadow_sprite.material = shadow_material
	
	# 4. Connect to Sun changes
	Sun.sun_changed.connect(_update_appearance)
	
	# 5. Initial Update
	_update_appearance()
	_sync_texture_data()

func _process(_delta):
	# Only run every frame if the object animates (moves, walks, changes frame)
	if is_dynamic and parent_sprite:
		_sync_texture_data()

func _sync_texture_data():
	# Copy all visual properties from the parent to the shadow
	shadow_sprite.texture = parent_sprite.texture
	shadow_sprite.hframes = parent_sprite.hframes
	shadow_sprite.vframes = parent_sprite.vframes
	shadow_sprite.frame = parent_sprite.frame
	shadow_sprite.flip_h = parent_sprite.flip_h
	shadow_sprite.offset = parent_sprite.offset
	shadow_sprite.texture = parent_sprite.texture

func _update_appearance():
	# Update Shader Color
	shadow_material.set_shader_parameter("shadow_color", Sun.shadow_color)
	# Update Position Offset (The "Height" Logic)
	# The shadow is a child of the parent, so position is local relative to parent
	shadow_sprite.position = (Sun.global_offset * height_multiplier).rotated(-parent_sprite.rotation)
