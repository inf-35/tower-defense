extends EffectPrototype
class_name DamageBoostOnStatusEffect

@export var required_status: Attributes.Status = Attributes.Status.FROST ## seeking status for the unit being damaged
@export var damage_bonus_per_stack: float = 0.20 ## increased damage per stack

func _init() -> void:
	# HIT_RECEIVED allows us to modify incoming damage based on the unit's state
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

	if not victim.modifiers_component.has_status(required_status): #check for status
		return

	var stacks: float = 0.0
	if victim.modifiers_component._status_effects.has(required_status):
		stacks = victim.modifiers_component._status_effects[required_status].stack
	
	if stacks <= 0.0:
		return

	var multiplier: float = 1.0 + (stacks * damage_bonus_per_stack)
	hit_data.damage *= multiplier
