extends Area2D
class_name PrismLaser

@export var collision_shape: CollisionShape2D
@export var color_start: Color = Color(1.0, 0.8, 0.2, 0.424)
@export var color_end: Color = Color(1.0, 0.8, 0.2, 1.0)
@export var pulse_speed: float = 5.0

var prism_a: Tower
var prism_b: Tower

var _targets_in_area: Array[Unit] = []
var _time_passed: float = 0.0

func _ready() -> void:
	if not _has_valid_prisms():
		queue_free()
		return

	self.collision_layer = 0
	self.collision_mask = Hitbox.get_mask(not prism_a.hostile)
	self.monitoring = true
	self.monitorable = false
	self.z_index = Layers.ALLIED_PROJECTILES

	self.area_entered.connect(_on_area_entered)
	self.area_exited.connect(_on_area_exited)

func _process(delta: float) -> void:
	if not _has_valid_prisms():
		queue_free()
		return

	_time_passed += delta
	queue_redraw()

func _on_area_entered(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		if not _targets_in_area.has(area.unit):
			_targets_in_area.append(area.unit)

func _on_area_exited(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		_targets_in_area.erase(area.unit)

func get_targets() -> Array[Unit]: ##returns the current valid units intersecting this beam without applying damage itself
	if not _has_valid_prisms():
		queue_free()
		return []

	var valid_targets: Array[Unit] = []
	for i: int in range(_targets_in_area.size() - 1, -1, -1):
		var target: Unit = _targets_in_area[i]
		if not is_instance_valid(target):
			_targets_in_area.remove_at(i)
			continue
		valid_targets.append(target)
	return valid_targets

func _draw() -> void:
	if not is_instance_valid(collision_shape) or not collision_shape.shape is RectangleShape2D:
		return

	var rect_shape: RectangleShape2D = collision_shape.shape as RectangleShape2D

	var rect: Rect2 = Rect2(-rect_shape.size / 2.0, rect_shape.size)

	var t: float = (sin(_time_passed * pulse_speed) + 1.0) / 2.0
	var current_color: Color = color_start.lerp(color_end, t)

	draw_rect(rect, current_color, true)

func _has_valid_prisms() -> bool:
	return _is_valid_prism(prism_a) and _is_valid_prism(prism_b)

func _is_valid_prism(prism: Tower) -> bool:
	return is_instance_valid(prism) and not prism.is_queued_for_deletion() and not prism.disabled
