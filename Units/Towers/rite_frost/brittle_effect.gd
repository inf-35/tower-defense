extends EffectPrototype
class_name BrittleEffect

@export var minimum_trigger_damage: float = 2.0 ##hit must meet this post-modifier damage before brittle applies
@export var damage_multiplier: float = 2.0 ##one-stack damage multiplier; extra stacks add the same bonus again

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	counts_as_status = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##amplifies every sufficiently large hit while brittle remains active
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data or hit_data.negate:
		return
	if hit_data.damage < minimum_trigger_damage:
		return

	hit_data.damage = hit_data.damage * get_damage_multiplier(instance)
	trigger_source_tower_pulse(instance)

func get_damage_multiplier(instance: EffectInstance) -> float: ##returns the linear multiplier contributed by current brittle stacks
	return 1.0 + ((damage_multiplier - 1.0) * instance.stacks)
