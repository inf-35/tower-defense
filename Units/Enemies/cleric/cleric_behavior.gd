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
		var statuslikes: Dictionary = ally.get_statuslikes()
		var statuses: Array[StatusEffect]
		statuses.assign(statuslikes.get(&"statuses", []))
		var effect_instances: Array[EffectInstance]
		effect_instances.assign(statuslikes.get(&"effects", []))

		for status: StatusEffect in statuses:
			if not is_instance_valid(status):
				continue
			if status.stack <= 0.0:
				continue

			status.stack = 0.0
			ally.modifiers_component.update_status(status)

		for effect_instance: EffectInstance in effect_instances:
			if not is_instance_valid(effect_instance):
				continue
			if not is_instance_valid(effect_instance.effect_prototype):
				continue

			ally.remove_effect(effect_instance.effect_prototype)

		ally.modifiers_component.add_status(Attributes.Status.CLEANSE, 1.0, cleanse_duration, unit.unit_id)
		did_apply_cleanse = true
		_spawn_cleanse_vfx(ally)

	if did_apply_cleanse:
		_play_animation(&"cast")
		_spawn_pulse_vfx()

	return true

func _spawn_cleanse_vfx(target: Unit) -> void:
	if not is_instance_valid(target.graphics):
		return

	var tween: Tween = create_tween()
	tween.tween_property(target, "scale", Vector2(1.18, 1.18), 0.1)
	tween.tween_property(target, "scale", Vector2.ONE, 0.1)

func _spawn_pulse_vfx() -> void:
	_spawn_aura_ring_pulse(PULSE_COLOR)
