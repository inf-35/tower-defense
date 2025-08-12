# A lightweight object to track the runtime state of one effect.
class_name VFXInstance
extends RefCounted

var vfx_info: VFXInfo  # The blueprint this instance is based on.
var canvas_item: RID  # The RID of the visual on the RenderingServer.

var position: Vector2
var velocity: Vector2
var rotation: float = 0.0 # In radians

var age: float = 0.0      # Current time since creation.
var lifetime: float = 0.0
