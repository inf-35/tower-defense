# ruined_ground_slow_effect.gd
extends GlobalEffect
class_name StatusInflictCausesHitRelic

# --- configuration (designer-friendly) ---
@export var need_qualifying_status: bool = true ##whether the qualifying status is necessary
@export var qualifying_status: Attributes.Status ##the existing status effect needed to qualify
@export var qualifying_threshold: float = 0.0 ##threshold of stacks needed to qualify
@export var trigger_status: Attributes.Status ##the status effect needed to cause the hit
@export var trigger_threshold: float = 0.0 ##threshold of stacks needed to cause hit

@export var attack_data: AttackData ##describes the attack that is triggered (targetless attack)

func initialise() -> void:
	Player.on_event.connect(_on_event)

func _on_event(unit: Unit, game_event: GameEvent):
	if game_event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	if need_qualifying_status:
		if not is_instance_valid(unit.modifiers_component):
			return
		if not unit.modifiers_component.has_status(qualifying_status, qualifying_threshold):
			return
	
	var trigger_hit_data: HitData = game_event.data as HitData
	if not trigger_hit_data.status_effects.has(trigger_status):
		return
	
	var input_status_stacks: float = trigger_hit_data.status_effects[trigger_status].x
	if input_status_stacks >= trigger_threshold:
		# create the HitData for the explosion from our configured prototype
		var secondary_hit: HitData = attack_data.generate_hit_data()
		secondary_hit.recursion = trigger_hit_data.recursion + 1
		print("recursion: ", secondary_hit.recursion)
		secondary_hit.source = trigger_hit_data.source #use the source of the triggering hit
		secondary_hit.target = null # this is a targetless AOE
		
		# the explosion should target similarly affiliated enemies
		secondary_hit.target_affiliation = trigger_hit_data.target_affiliation
		
		# create the DeliveryData for an instantaneous, centered AOE
		var delivery_data := DeliveryData.new()
		delivery_data.use_source_position_override = true
		delivery_data.source_position = unit.global_position #start the projectile at the unit's position
		delivery_data.delivery_method = DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT
		delivery_data.intercept_position = unit.global_position # center the explosion on the dying unit
		
		# command the CombatManager to resolve this new hit
		CombatManager.resolve_hit(secondary_hit, delivery_data)
	
