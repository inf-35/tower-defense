extends EffectPrototype
class_name DynamiteEffect

@export var damage_multiplier: float = 2.5 ##taken from the tower's authored base damage
@export var attack_data: AttackData ##visuals for the explosion

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

	var tower: Tower = event.unit as Tower
	if not is_instance_valid(tower) or tower.hostile or tower.environmental:
		return

	if not Run.phases.current_phase == Run.phases.GamePhase.COMBAT_WAVE:
		return

	var hit_data: HitData = event.data as HitData
	if not _is_tower_hit(hit_data):
		return

	_trigger_explosion(_instance, hit_data, tower)

func _trigger_explosion(instance: EffectInstance, parent_hit: HitData, tower: Tower) -> void:
	if attack_data == null:
		push_warning("DynamiteEffect: No AttackData assigned!")
		return

	var base_damage: float = 0.0
	if is_instance_valid(tower.attack_component) and tower.attack_component.attack_data:
		base_damage = tower.attack_component.attack_data.damage

	var final_damage: float = base_damage * damage_multiplier

	#create the reaction hit
	var hit_data: HitData = attack_data.generate_generic_hit_data()
	if not hit_data.derive_lineage_from(parent_hit, instance):
		return
	hit_data.source = tower
	hit_data.target = null #targetless aoe
	hit_data.target_affiliation = not tower.hostile
	hit_data.attack_id = AttackComponent.get_next_attack_id()
	hit_data.primary = false
	hit_data.damage = final_damage

	#configure delivery to happen instantly at the unit's location
	var delivery_data: DeliveryData = attack_data.generate_generic_delivery_data()
	delivery_data.use_source_position_override = true
	delivery_data.source_position = tower.global_position
	delivery_data.intercept_position = tower.global_position

	CombatManager.resolve_hit(hit_data, delivery_data)
	UI.floating_text_manager.show_icon(icon, tower.global_position)

func _is_tower_hit(hit_data: HitData) -> bool: ##allows any positive allied tower hit to detonate, including lethal hits
	if not is_instance_valid(hit_data) or hit_data.negate or hit_data.damage <= 0.0:
		return false
	return true
