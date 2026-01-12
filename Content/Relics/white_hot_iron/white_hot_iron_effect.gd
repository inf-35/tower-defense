extends EffectPrototype
class_name WhiteHotIronEffect

@export var damage_threshold: float = 6.0 ##damage threshold (in a single hit) needed to trigger the effect
@export var spark_count: int = 3 ##number of sparks fired
@export var stack_transfer_ratio: float = 0.5 ## 50% transfer
@export var required_status: Attributes.Status = Attributes.Status.BURN
@export var spark_attack_data: AttackData ## defines the spark projectile

const RECURSION_BLOCK_TIME: float = 0.15 ## when units trigger this effect, they are blocked for this amount of time from retriggering it (to prevent recursion)

class WhiteHotIronState extends RefCounted:
	var cooldown: Dictionary[Unit, float] = {}

#TODO: implement a cooldown to prevent infinite recursion
func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = WhiteHotIronState.new()
	return instance

func _handle_attach(_i: EffectInstance) -> void: pass
func _handle_detach(_i: EffectInstance) -> void: pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	var hit_data := event.data as HitData
	if not hit_data or not is_instance_valid(hit_data.target):
		return

	if hit_data.damage < damage_threshold:
		return

	var victim: Unit = hit_data.target
	
	if not victim.hostile: #victim must be an enemy
		return
	
	# is the victim burning?
	if not is_instance_valid(victim.modifiers_component):
		return
	if not victim.modifiers_component.has_status(required_status):
		return
		
	# calculate transfer
	var current_stacks: float = 0.0
	var current_duration: float = 0.0
	
	# access internal dict safely
	var status_obj = victim.modifiers_component._status_effects[required_status]
	current_stacks = status_obj.stack
	current_duration = status_obj.cooldown

	var stacks_to_apply: float = current_stacks * stack_transfer_ratio
	
	if stacks_to_apply < 0.4:
		return #dont bother applying if stacks < 0.4.
	_spawn_sparks(stacks_to_apply, current_duration, hit_data)
	
	#apply cooldown (bar this unit from retriggering the effect temporarily)
	var state := instance.state as WhiteHotIronState
	state.cooldown[victim] = RECURSION_BLOCK_TIME
	victim.tree_exiting.connect(func():
		state.cooldown.erase(victim),
		CONNECT_ONE_SHOT
	)

func _spawn_sparks(stacks: int, duration: float, original_hit_data: HitData) -> void:
	if spark_attack_data == null: return
	
	var victim: Unit = original_hit_data.target
	var source: Unit = original_hit_data.source
	
	var origin: Vector2 = victim.global_position
	
	for i in spark_count:
		var dir = Vector2.UP.rotated(randf() * TAU)
		
		var hit_data := spark_attack_data.generate_generic_hit_data()
		hit_data.recursion = original_hit_data.recursion + 1
		hit_data.source = source
		hit_data.target = null
		hit_data.target_affiliation = victim.hostile
		hit_data.status_effects[required_status] = Vector2(stacks, duration)

		var delivery := spark_attack_data.generate_generic_delivery_data()
		delivery.delivery_method = DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED
		delivery.excluded_units = [victim]
		delivery.use_source_position_override = true
		delivery.source_position = origin
		delivery.use_initial_velocity_override = true
		delivery.initial_velocity = dir * spark_attack_data.projectile_speed
		
		CombatManager.resolve_hit(hit_data, delivery)

func on_tick(instance: EffectInstance, delta: float) -> void:
	var state := instance.state as WhiteHotIronState
	for unit: Unit in state.cooldown:
		state.cooldown[unit] -= delta
		if state.cooldown[unit] <= 0.0:
			state.cooldown.erase(unit)
