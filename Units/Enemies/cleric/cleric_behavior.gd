extends HealerBehavior
class_name ClericBehavior

const PULSE_COLOR: Color = Color(0.35, 0.65, 1.0, 0.85)

@export var cleanse_duration: float = 2.0 ##how long cleansed enemies reject incoming statuses

func _perform_heal_pulse() -> bool:
	var did_apply_cleanse: bool = false
	var valid_allies: Array[Unit] = []

	for ally: Unit in _allies_in_range:
		if is_instance_valid(ally) and is_instance_valid(ally.modifiers_component):
			valid_allies.append(ally)
	_allies_in_range = valid_allies

	for ally: Unit in _allies_in_range:
		_clear_statuses(ally)
		ally.modifiers_component.add_status(Attributes.Status.CLEANSE, 1.0, cleanse_duration, unit.unit_id)
		did_apply_cleanse = true
		_spawn_cleanse_vfx(ally)

	if did_apply_cleanse:
		_play_animation(&"cast")
		_spawn_pulse_vfx()

	return true

func _clear_statuses(target: Unit) -> bool:
	if not is_instance_valid(target.modifiers_component):
		return false

	var statuses: Array[StatusEffect] = []
	statuses.assign(target.modifiers_component._status_effects.values())
	var did_clear: bool = false

	for status: StatusEffect in statuses:
		if not is_instance_valid(status):
			continue
		if status.stack <= 0.0:
			continue

		status.stack = 0.0
		target.modifiers_component.update_status(status)
		did_clear = true

	return did_clear

func _spawn_cleanse_vfx(target: Unit) -> void:
	if not is_instance_valid(target.graphics):
		return

	var tween: Tween = create_tween()
	tween.tween_property(target, "scale", Vector2(1.18, 1.18), 0.1)
	tween.tween_property(target, "scale", Vector2.ONE, 0.1)

func _spawn_pulse_vfx() -> void:
	if not is_instance_valid(unit):
		return

	var pulse: Line2D = Line2D.new()
	pulse.width = 2.0
	pulse.default_color = PULSE_COLOR
	pulse.closed = true

	var points: PackedVector2Array = []
	var steps: int = 16
	for i: int in range(steps):
		var angle: float = (float(i) / steps) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * 10.0)
	pulse.points = points

	unit.add_child(pulse)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2.ONE * (heal_range / 10.0), 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.5)
	tween.tween_callback(pulse.queue_free).set_delay(0.5)
