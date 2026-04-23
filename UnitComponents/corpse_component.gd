extends UnitComponent
class_name CorpseComponent

const THROW_DURATION: float = 0.35
const LINGER_DURATION: float = 0.4
const FADE_DURATION: float = 1.5
const THROW_DISTANCE_RANGE: Vector2 = Vector2(0.3, 0.5)
const ARC_HEIGHT_RANGE: Vector2 = Vector2(0.2, 0.3)
const SPIN_RANGE: Vector2 = Vector2(0.4, 0.6)

func release_corpse(hit_report_data: HitReportData) -> void:
	if not is_instance_valid(unit) or not is_instance_valid(unit.graphics) or not is_instance_valid(unit.get_parent()):
		return

	var corpse_root := Node2D.new()
	corpse_root.name = "%s Corpse" % unit.name
	corpse_root.z_as_relative = false
	corpse_root.z_index = Layers.NON_COLLIDABLE_OBJECTS
	unit.get_parent().add_child(corpse_root)
	corpse_root.global_position = unit.global_position

	var corpse_graphics := unit.graphics
	corpse_graphics.reparent(corpse_root, true)
	corpse_graphics.z_index = 0
	corpse_graphics.z_as_relative = true
	unit.graphics = null

	_animate_corpse(corpse_root, corpse_graphics, hit_report_data)

func _animate_corpse(corpse_root: Node2D, corpse_graphics: Sprite2D, hit_report_data: HitReportData) -> void:
	var throw_direction := hit_report_data.velocity
	if throw_direction.length_squared() < 0.001 and is_instance_valid(unit.movement_component):
		throw_direction = unit.movement_component.velocity
	if throw_direction.length_squared() < 0.001:
		throw_direction = Vector2.RIGHT.rotated(randf() * TAU)
	throw_direction = throw_direction.normalized().rotated(randf_range(-0.45, 0.45))

	var start_position := corpse_root.global_position
	var end_position := start_position + throw_direction * randf_range(
		THROW_DISTANCE_RANGE.x,
		THROW_DISTANCE_RANGE.y
	) * Island.CELL_SIZE
	var base_graphics_position := corpse_graphics.position
	var base_rotation := corpse_graphics.rotation
	var arc_height := randf_range(ARC_HEIGHT_RANGE.x, ARC_HEIGHT_RANGE.y) * Island.CELL_SIZE
	var spin := randf_range(SPIN_RANGE.x, SPIN_RANGE.y)
	var corpse_material := _prepare_corpse_material(corpse_graphics)
	var update_arc := func(progress: float) -> void:
		if not is_instance_valid(corpse_root) or not is_instance_valid(corpse_graphics):
			return

		corpse_root.global_position = start_position.lerp(end_position, progress)
		corpse_graphics.position = base_graphics_position + Vector2(0.0, -sin(progress * PI) * arc_height)
		corpse_graphics.rotation = base_rotation + spin * progress

	var corpse_tween := corpse_root.create_tween()
	corpse_tween.tween_method(update_arc, 0.0, 1.0, THROW_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	corpse_tween.tween_interval(LINGER_DURATION)
	if is_instance_valid(corpse_material):
		corpse_tween.tween_property(corpse_material, "shader_parameter/transparency", 0.0, FADE_DURATION)
	else:
		corpse_tween.tween_property(corpse_graphics, "modulate:a", 0.0, FADE_DURATION)
	corpse_tween.tween_callback(Callable(corpse_root, "queue_free"))

func _prepare_corpse_material(corpse_graphics: Sprite2D) -> ShaderMaterial:
	var corpse_material := corpse_graphics.material as ShaderMaterial
	if not is_instance_valid(corpse_material):
		return null

	corpse_material = corpse_material.duplicate() as ShaderMaterial
	corpse_graphics.material = corpse_material
	corpse_material.set_shader_parameter(&"flash_intensity", 0.0)
	corpse_material.set_shader_parameter(&"overlay_color", Color(0.0, 0.0, 0.0, 0.0))
	corpse_material.set_shader_parameter(&"transparency", 1.0)
	return corpse_material

func get_save_data() -> Dictionary:
	return {}
