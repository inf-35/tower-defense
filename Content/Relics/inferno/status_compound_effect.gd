extends EffectPrototype
class_name StatusCompoundEffect

@export var status_type: Attributes.Status = Attributes.Status.BURN
@export var trigger_chance: float = 0.10 ##from 0 to 1
@export var bonus_stacks: float = 1.0 ##amount to add to the existing pool

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	var hit_data := event.data as HitData
	if not hit_data:
		return
		
	var victim: Unit = event.unit
	if not is_instance_valid(victim) or not is_instance_valid(victim.modifiers_component):
		return

	if not victim.modifiers_component.has_status(status_type): #enemy must already be burning
		return

	if not hit_data.status_effects.has(status_type): #hit must also apply burn
		return

	if randf() > trigger_chance: # rng check
		return
	
	var stacks: float = victim.modifiers_component.get_status_count(status_type) + bonus_stacks
	# take the duration from the incoming hit to keep it consistent with the attack
	var incoming_duration: float = hit_data.status_effects[status_type].y
	victim.modifiers_component.add_status(status_type, stacks, incoming_duration)
