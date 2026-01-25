extends EffectPrototype
class_name DynamiteEffect

@export var damage_multiplier: float = 2.0 ## taken from the tower's base dmg
@export var attack_data: AttackData ## Visuals for the explosion

func _init() -> void:
	event_hooks = [GameEvent.EventType.DIED]
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
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dying_unit: Unit = event.unit
	if not is_instance_valid(dying_unit) or not dying_unit is Tower:
		return

	if not Phases.current_phase == Phases.GamePhase.COMBAT_WAVE:
		return

	_trigger_explosion(dying_unit as Tower)

func _trigger_explosion(tower: Tower) -> void:
	if attack_data == null:
		push_warning("DynamiteEffect: No AttackData assigned!")
		return
	var base_dmg: float = 0.0
	if is_instance_valid(tower.attack_component) and tower.attack_component.attack_data:
		base_dmg = tower.attack_component.get_stat(
			tower.modifiers_component, 
			tower.attack_component.attack_data, 
			Attributes.id.DAMAGE
		)
		
	var final_dmg: float = base_dmg * damage_multiplier
	print(final_dmg)

	# create the reaction hit
	var hit_data: HitData = attack_data.generate_generic_hit_data()
	hit_data.target = null # Targetless AOE
	hit_data.target_affiliation = not tower.hostile
	hit_data.damage = final_dmg
	
	# configure delivery to happen instantly at the unit's location
	var delivery_data: DeliveryData = attack_data.generate_generic_delivery_data()
	delivery_data.use_source_position_override = true
	delivery_data.source_position = tower.global_position 
	delivery_data.intercept_position = tower.global_position
	
	CombatManager.resolve_hit(hit_data, delivery_data)
