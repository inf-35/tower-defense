class_name VFXInfo
extends Resource

const INFINITE_LIFETIME: float = -1.0 ##use for vfx which have unbounded lifetimes
#the new enum to select the renderer.
enum VFXType { TEXTURE, CIRCLE, RECTANGLE, GPU_PARTICLES, LINE }
@export var vfx_type: VFXType = VFXType.TEXTURE

@export_group("Scene")
@export var is_scene: bool = false ##if true, ignores procedural vfx and instantiates scene below
@export var scene: PackedScene ##vfx scene to instantiate
@export var is_persistent: bool = false ##if true, attaches to host unit and reuses the same instance
@export_subgroup("RadialPulse")
@export var color_gradient: Gradient
@export var is_full_circle: bool = true
@export var start_angle_deg: float = -45.0
@export var end_angle_deg: float = 45.0
#--- properties for texture type ---
@export_group("Texture")
@export var texture: Texture2D
@export var is_spritesheet: bool = false
@export var h_frames: int = 1
@export var v_frames: int = 1
@export var fps: float = 12.0

#--- properties for geometry types ---
@export_group("Geometry")
@export var radius: float = 10.0 #for circle
@export var size: Vector2 = Vector2(20, 20) #for rectangle
@export var filled: bool = true #for rectangle, false creates an outline.
@export var primitive_width: float = 2.0 #for outline width.

@export_group("Line")
@export var line_width: float = 3.0
@export var line_length: float = 20.0

#--- universal behavior properties ---
@export_category("Universal")
@export var scale: float = 1.0
@export var lifetime: float = 1.0
@export var rotation_mode: RotationMode = RotationMode.STATIC #changed default
enum RotationMode { STATIC, FACE_VELOCITY, SPIN }
@export var spin_speed: float = 180.0
@export var graphical_layer: int = 1000

@export var scale_over_lifetime: Curve
@export var color_over_lifetime: Gradient
