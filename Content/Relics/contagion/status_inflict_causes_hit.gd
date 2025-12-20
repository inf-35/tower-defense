extends EffectPrototype
class_name StatusReactionEffect

# --- configuration ---
@export_group("Conditions")
@export var need_qualifying_status: bool = true ## check if the unit already has a specific status
@export var qualifying_status: Attributes.Status ## the existing status effect needed to qualify
@export var qualifying_threshold: float = 0.0 ## stacks needed on the unit

@export var trigger_status: Attributes.Status ## the status effect being applied in the hit
@export var trigger_threshold: float = 0.0 ## stacks needed in the hit to cause reaction

@export_group("Reaction")
@export var attack_data: AttackData ## describes the attack triggered (e.g. Explosion)

func _init() -> void:
	# listen for whenever any unit takes a hit
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	# stateless effect, so no custom state object needed
	return instance

# --- event handlers ---
func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	var trigger_hit_data := event.data as HitData
	var target_unit := trigger_hit_data.target
	
	if not is_instance_valid(target_unit):
		return

	# check qualifying status
	if need_qualifying_status:
		if not is_instance_valid(target_unit.modifiers_component):
			return
		if not target_unit.modifiers_component.has_status(qualifying_status, qualifying_threshold):
			return
	
	# check trigger status
	if not trigger_hit_data.status_effects.has(trigger_status):
		return
	
	var input_status_stacks: float = trigger_hit_data.status_effects[trigger_status].x
	
	if input_status_stacks >= trigger_threshold:
		_execute_reaction(trigger_hit_data, target_unit)

func _execute_reaction(trigger_hit: HitData, center_unit: Unit) -> void:
	if attack_data == null:
		push_warning("StatusReactionEffect: Triggered but no AttackData assigned.")
		return

	# create the reaction hit
	var secondary_hit: HitData = attack_data.generate_generic_hit_data()
	
	# inherit recursion depth to prevent infinite loops
	secondary_hit.recursion = trigger_hit.recursion + 1
	
	# attribute the damage to the original attacker
	secondary_hit.source = trigger_hit.source 
	secondary_hit.target = null # Targetless AOE
	secondary_hit.target_affiliation = trigger_hit.target_affiliation
	
	# configure delivery to happen instantly at the unit's location
	var delivery_data: DeliveryData = attack_data.generate_generic_delivery_data()
	delivery_data.use_source_position_override = true
	delivery_data.source_position = center_unit.global_position 
	delivery_data.intercept_position = center_unit.global_position
	
	CombatManager.resolve_hit(secondary_hit, delivery_data)
