extends EffectPrototype
class_name FistRiteEffect

@export var damage_bonus_per_status_stack: float = 0.40 ## damage bonus per stack converted

# NOTE: this effect is reactive for statuses, but multiplicative for damage
# in the end i chose reactive, but both fit

func _init() -> void:
	# PRE_HIT_DEALT allows modifying the HitData (Damage/Status) before the projectile spawns
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	# stateless effect (reactive)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return
	
	var hit_data := event.data as HitData
	if not hit_data:
		return
		
	# tally the potential status effects
	var total_potential_stacks: float = 0.0
	
	for status_key in hit_data.status_effects:
		var payload: Vector2 = hit_data.status_effects[status_key]
		total_potential_stacks += payload.x # add the stack count

	if total_potential_stacks <= 0.0:
		return

	var total_multiplier: float = 1.0 + (total_potential_stacks * damage_bonus_per_status_stack)
	print(total_potential_stacks, " ", total_multiplier," ", instance.stacks)
	hit_data.damage *= total_multiplier #apply damage bonus
	hit_data.status_effects.clear() #remove all status effects
