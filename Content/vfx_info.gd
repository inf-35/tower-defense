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

@export_group("Swirl Line")
@export var swirl_particle_texture: Texture2D = preload("res://Assets/particle_whirl.png") ##sprite used by authored swirl-line effects when no bespoke texture is supplied
@export var swirl_color: Color = Color(1.0, 1.0, 1.0, 0.35) ##base tint and opacity applied to every swirl particle before lifetime fade
@export var swirl_width: float = 10.0 ##world-space beam thickness used when sampling lateral offsets around the line segment
@export var swirl_particles_per_tile: float = 2.0 ##density budget measured against island cell length so longer links naturally receive more particles
@export var swirl_scale_min: float = 0.45 ##minimum per-particle sprite scale for the authored line effect
@export var swirl_scale_max: float = 0.85 ##maximum per-particle sprite scale for the authored line effect
@export var swirl_drift_speed_min: float = 4.0 ##minimum particle drift speed after spawn so the line can feel soft or energetic
@export var swirl_drift_speed_max: float = 12.0 ##maximum particle drift speed after spawn so the line can feel soft or energetic
@export var swirl_drift_angle_noise_deg: float = 35.0 ##random angular wobble applied to particle drift so the line does not collapse into a rigid laser

@export_group("Aoe Particles")
@export var aoe_particles_enabled: bool = false ##when true, aoe-capable attacks can stamp a dense particle field across their affected shape
@export var aoe_particle_texture: Texture2D = preload("res://Assets/particle_whirl.png") ##base sprite used for each particle in the aoe field
@export var aoe_particle_color: Color = Color(1.0, 1.0, 1.0, 0.35) ##tint applied to every spawned particle before lifetime fading
@export var aoe_particles_per_cell: float = 4.0 ##rough density budget measured in particles per covered island cell
@export var aoe_particle_lifetime: float = 0.35 ##how long the field marker persists before fading out completely
@export var aoe_particle_scale_min: float = 0.45 ##minimum per-particle sprite scale, in the same world-space convention as other vfx
@export var aoe_particle_scale_max: float = 0.9 ##maximum per-particle sprite scale, allowing one resource to feel either misty or chunky
@export var aoe_particle_spin_speed_min: float = -45.0 ##minimum per-particle spin rate in degrees per second
@export var aoe_particle_spin_speed_max: float = 45.0 ##maximum per-particle spin rate in degrees per second
@export var aoe_particle_drift_speed_min: float = 6.0 ##minimum outward drift speed in world units per second
@export var aoe_particle_drift_speed_max: float = 18.0 ##maximum outward drift speed in world units per second
@export var aoe_particle_drift_angle_noise_deg: float = 20.0 ##random angular wobble added around the outward direction so fields do not expand as a perfect starburst

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
