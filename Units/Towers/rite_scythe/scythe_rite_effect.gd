extends EffectPrototype
class_name ScytheRiteEffect

@export var bonus_per_percent: float = 1.0 ## +1% dmg per 1% HP condition
@export var invert_logic: bool = false ## false = Missing HP (Executioner), True = Current HP (Reverse)

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_i): pass
func _handle_detach(_i): pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT: return
	
	var hit_data = event.data as HitData
	if not hit_data: return
	
	var target = hit_data.target
	if not is_instance_valid(target) or not is_instance_valid(target.health_component):
		return
		
	# 1. Calculate Health Percentage (0.0 to 1.0)
	var hp_ratio = target.health_component.health / target.health_component.max_health
	
	# 2. Determine Factor
	var factor: float = 0.0
	if invert_logic:
		# Based on CURRENT health (100% HP = Max Bonus)
		factor = hp_ratio
	else:
		# Based on MISSING health (0% HP = Max Bonus)
		factor = 1.0 - hp_ratio
		
	# 3. Calculate Bonus
	# e.g. 50% missing * 1.0 bonus = +50% damage
	# Multiplier = 1.0 + (0.5 * 1.0) = 1.5
	var multiplier = 1.0 + (factor * bonus_per_percent * instance.stacks)
	print(factor, " ", hit_data.damage, " ", hit_data.damage * multiplier)
	hit_data.damage *= multiplier
