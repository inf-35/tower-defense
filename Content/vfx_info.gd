class_name VFXInfo
extends Resource

const INFINITE_LIFETIME: float = -1.0 ##use for vfx which have unbounded lifetimes
# The new enum to select the renderer.
enum VFXType { TEXTURE, CIRCLE, RECTANGLE, GPU_PARTICLES, LINE }
@export var vfx_type: VFXType = VFXType.TEXTURE

# --- Properties for TEXTURE type ---
@export_category("Texture")
@export var texture: Texture2D
@export var is_spritesheet: bool = false
@export var h_frames: int = 1
@export var v_frames: int = 1
@export var fps: float = 12.0

# --- Properties for GEOMETRY types ---
@export_category("Geometry")
@export var radius: float = 10.0 # For CIRCLE
@export var size: Vector2 = Vector2(20, 20) # For RECTANGLE
@export var filled: bool = true # For RECTANGLE, false creates an outline.
@export var primitive_width: float = 2.0 # For outline width.

@export_category("Line")
@export var line_width: float = 3.0
@export var line_length: float = 20.0

# --- Universal Behavior Properties ---
@export_category("Universal")
@export var lifetime: float = 1.0
@export var rotation_mode: RotationMode = RotationMode.STATIC # Changed default
enum RotationMode { STATIC, FACE_VELOCITY, SPIN }
@export var spin_speed: float = 360.0
@export var graphical_layer: int = 1000

@export var scale_over_lifetime: Curve
@export var color_over_lifetime: Gradient


## This function dynamically changes what's visible in the Inspector.
## It makes the resource much cleaner and less error-prone to use.
#func _get_property_list() -> Array:
	#var properties: Array = []
	#
	## --- Add properties visible for ALL types ---
	#properties.append({ "name": "vfx_type", "type": TYPE_INT, "usage": PROPERTY_USAGE_DEFAULT, "hint": PROPERTY_HINT_ENUM, "hint_string": "Texture,Circle,Rectangle" })
	#
	## --- Add properties based on the selected type ---
	#match vfx_type:
		#VFXType.TEXTURE:
			#properties.append({ "name": "texture", "type": TYPE_OBJECT, "usage": PROPERTY_USAGE_DEFAULT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Texture2D" })
			#properties.append({ "name": "is_spritesheet", "type": TYPE_BOOL, "usage": PROPERTY_USAGE_DEFAULT })
			#if is_spritesheet:
				#properties.append({ "name": "h_frames", "type": TYPE_INT, "usage": PROPERTY_USAGE_DEFAULT })
				#properties.append({ "name": "v_frames", "type": TYPE_INT, "usage": PROPERTY_USAGE_DEFAULT })
				#properties.append({ "name": "fps", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_DEFAULT })
#
		#VFXType.CIRCLE:
			#properties.append({ "name": "radius", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_DEFAULT })
#
		#VFXType.RECTANGLE:
			#properties.append({ "name": "size", "type": TYPE_VECTOR2, "usage": PROPERTY_USAGE_DEFAULT })
			#properties.append({ "name": "filled", "type": TYPE_BOOL, "usage": PROPERTY_USAGE_DEFAULT })
			#if not filled:
				#properties.append({ "name": "primitive_width", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_DEFAULT })
#
	#return properties
