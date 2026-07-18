extends EffectPrototype
class_name BrittleEffect

@export var minimum_trigger_damage: float = 3.0 ##hit must exceed this post-modifier damage before brittle is consumed
@export var damage_multiplier: float = 2.0 ##damage multiplier applied to the qualifying hit

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##doubles the next sufficiently large hit, then removes itself
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data or hit_data.negate:
		return
	if hit_data.damage <= minimum_trigger_damage:
		return

	hit_data.damage *= damage_multiplier
	_consume(instance)

func _consume(instance: EffectInstance) -> void:
	if not is_instance_valid(instance.host):
		return

	if instance.should_show_status_icon():
		instance.host.effect_display_removed.emit(instance)

	instance.enabled = false
	trigger_source_tower_pulse(instance)
	instance.host.remove_effect.call_deferred(instance.effect_prototype)
