#a lightweight object to track the runtime state of one effect.
class_name VFXInstance
extends RefCounted

var vfx_info: VFXInfo  #the blueprint this instance is based on.
var canvas_item: RID  #the rid of the visual on the renderingserver.

var position: Vector2
var velocity: Vector2
var rotation: float = 0.0 #in radians
var scale: Vector2 = Vector2.ONE #overall scale
var projectile_tints: Array[Color] = []
var projectile_tint_lifetime: float = -1.0

var age: float = 0.0      #current time since creation.
var lifetime: float = 0.00
var delete: bool = false #mark this vfx instance for deletion
