extends EffectPrototype
class_name AmbushEffect

@export var attack_data: AttackData ## defines the VFX and Delivery logic (should be configured as an AOE)

func _init() -> void:
	event_hooks = [GameEvent.EventType.TOWER_BUILT]
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
	if event.event_type != GameEvent.EventType.TOWER_BUILT:
		return
	# only trigger if the game is currently in a combat wave
	if Phases.current_phase != Phases.GamePhase.COMBAT_WAVE:
		return

	var data := event.data as BuildTowerData
	if not data or not is_instance_valid(data.tower):
		return
		
	var new_tower: Tower = data.tower
	_trigger_ambush_explosion(new_tower)

func _trigger_ambush_explosion(source_tower: Tower) -> void:
	if attack_data == null:
		push_warning("AmbushEffect: Triggered but no AttackData assigned.")
		return
	print("!!")
	# generate the hit payload from the designer-configured resource
	var hit_data: HitData = attack_data.generate_generic_hit_data()
	hit_data.source = source_tower
	hit_data.target_affiliation = not source_tower.hostile
	
	#instant centered aoe
	var delivery_data: DeliveryData = attack_data.generate_generic_delivery_data()
	delivery_data.use_source_position_override = true
	delivery_data.source_position = source_tower.global_position
	delivery_data.intercept_position = source_tower.global_position # explode exactly where the tower was built

	CombatManager.resolve_hit(hit_data, delivery_data)
