#a lightweight object to track the runtime state of one effect.
class_name VFXInstance
extends RefCounted

var vfx_info: VFXInfo  #the blueprint this instance is based on.
var canvas_item: RID  #the rid of the visual on the renderingserver.

var position: Vector2
var velocity: Vector2
var visual_velocity: Vector2
var trail_points: PackedVector2Array = PackedVector2Array()
var rotation: float = 0.0 #in radians
var vertical: float = 0.0
var vertical_velocity: float = 0.0
var vertical_gravity: float = 0.0
var arcing: bool = false
var scale: Vector2 = Vector2.ONE #overall scale
var is_projectile: bool = false
var uses_projectile_texture_multimesh: bool = false
var projectile_tints: Array[Color] = []
var projectile_tint_lifetime: float = -1.0
var projectile_chroma_strength: float = 0.0
var projectile_trail_chroma_strength: float = 0.0
var color_override: Color = Color.TRANSPARENT ##optional runtime hue replacement that preserves authored intensity and opacity

var age: float = 0.0      #current time since creation.
var lifetime: float = 0.00
var delete: bool = false #mark this vfx instance for deletion
