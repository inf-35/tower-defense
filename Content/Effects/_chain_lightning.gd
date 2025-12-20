extends EffectPrototype
class_name ChainLightningEffect

@export var max_jumps: int = 3
@export var jump_radius: float = 150.0
@export var damage_falloff_multiplier: float = 0.66

func _init() -> void:
	# listen for when the host deals a hit
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	# no persistent state required for chain lightning, so we don't assign instance.state
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	# reactive effect; no setup required
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	# reactive effect; no cleanup required
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return
	
	var hit_report := event.data as HitReportData
	# prevent infinite recursion loops by checking if this hit is already a child hit
	if not is_instance_valid(hit_report.target) or hit_report.recursion > 0:
		return

	# cast host to Tower to access attack components
	var host_tower := instance.host as Tower
	if not is_instance_valid(host_tower) or not is_instance_valid(host_tower.attack_component):
		return

	_execute_chain_lightning(host_tower, hit_report)

func _execute_chain_lightning(host: Tower, initial_report: HitReportData) -> void:
	var primary_target: Unit = initial_report.target
	var already_hit: Array[Unit] = [primary_target]
	var last_hit_target: Unit = primary_target
	
	# calculate base damage from the tower's stats
	var current_damage: float = host.attack_component.get_stat(
		host.modifiers_component, 
		host.attack_component.attack_data, 
		Attributes.id.DAMAGE
	)

	for i: int in range(max_jumps):
		# find a new target near the last one hit
		var next_target: Unit = _find_next_jump_target(last_hit_target, jump_radius, already_hit)
		
		if not is_instance_valid(next_target):
			break
			
		current_damage *= damage_falloff_multiplier
		
		# construct the new hit data
		var jump_hit_data: HitData = host.attack_component.generate_hit_data()
		jump_hit_data.source = host
		jump_hit_data.target = next_target
		jump_hit_data.target_affiliation = primary_target.hostile
		jump_hit_data.damage = current_damage #override damage
		jump_hit_data.recursion = initial_report.recursion + 1
		
		# use hitscan delivery to apply damage instantly from the position of the last enemy
		var delivery_data: DeliveryData = host.attack_component.attack_data.generate_delivery_data()
		delivery_data.use_source_position_override = true
		delivery_data.source_position = last_hit_target.global_position

		host.deal_hit(jump_hit_data, delivery_data)
		# update state for next loop iteration
		already_hit.append(next_target)
		last_hit_target = next_target

func _find_next_jump_target(from_target: Unit, radius: float, excluded_targets: Array[Unit]) -> Unit:
	# query combat manager for valid targets nearby
	var potential_targets: Array[Unit] = CombatManager.get_units_in_radius(
		radius, 
		from_target.global_position, 
		from_target.hostile, 
		excluded_targets
	)
	
	var closest_dist_sq: float = INF
	var closest_target: Unit = null
	
	# simple nearest-neighbor search
	for potential_target: Unit in potential_targets:
		var dist_sq: float = from_target.global_position.distance_squared_to(potential_target.global_position)
		if dist_sq < closest_dist_sq:
			closest_dist_sq = dist_sq
			closest_target = potential_target
				
	return closest_target
