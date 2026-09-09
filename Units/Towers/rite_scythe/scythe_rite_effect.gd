extends EffectPrototype
class_name ScytheRiteEffect

@export var negated_attacks_required: int = 2 ##base number of attacks banked before the payout attack
@export var payout_multiplier: float = 3.0 ##base multiplier applied to cumulative banked damage on the payout attack

class ScytheRiteState extends RefCounted:
	var seen_attack_ids: Dictionary[int, bool] = {}
	var payout_attack_ids: Dictionary[int, bool] = {}
	var payout_applied_attack_ids: Dictionary[int, bool] = {}
	var negated_attack_count: int = 0
	var banked_damage: float = 0.0

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = ScytheRiteState.new()
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##banks negated attacks, then releases scaled banked damage into the next attack
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data or hit_data.negate:
		return

	var state: ScytheRiteState = instance.state as ScytheRiteState
	if state == null:
		return

	var required_attacks: int = get_negated_attacks_required(instance)
	var attack_id: int = _get_attack_id(hit_data)
	var is_new_attack: bool = _consume_attack_id(attack_id, state.seen_attack_ids)
	if is_new_attack and state.negated_attack_count >= required_attacks:
		state.payout_attack_ids[attack_id] = true

	if state.payout_attack_ids.has(attack_id):
		_apply_payout(instance, hit_data, state, attack_id)
		return

	if is_new_attack:
		state.negated_attack_count += 1

	state.banked_damage += hit_data.damage
	hit_data.negate = true
	trigger_source_tower_pulse(instance)

func _apply_payout(instance: EffectInstance, hit_data: HitData, state: ScytheRiteState, attack_id: int) -> void:
	if state.payout_applied_attack_ids.has(attack_id):
		return

	if state.banked_damage <= 0.0:
		state.payout_applied_attack_ids[attack_id] = true
		state.negated_attack_count = 0
		return

	var banked_damage: float = state.banked_damage
	state.banked_damage = 0.0
	state.negated_attack_count = 0
	state.payout_applied_attack_ids[attack_id] = true
	hit_data.damage += banked_damage * get_payout_multiplier(instance)
	trigger_source_tower_pulse(instance)

func get_negated_attacks_required(instance: EffectInstance) -> int: ##returns skipped attacks after stacked rite copies compound as base^stacks
	return int(round(pow(float(maxi(negated_attacks_required, 1)), float(get_effect_stack_count(instance)))))

func get_payout_multiplier(instance: EffectInstance) -> float: ##returns payout scaling after stacked rite copies compound as base^stacks
	return pow(maxf(payout_multiplier, 1.0), float(get_effect_stack_count(instance)))

func get_effect_stack_count(instance: EffectInstance) -> int: ##returns the active rite stack count, treating lone instances as one stack
	return maxi(instance.stacks, 1)

func _consume_attack_id(attack_id: int, seen_attack_ids: Dictionary[int, bool]) -> bool:
	if seen_attack_ids.has(attack_id):
		return false

	seen_attack_ids[attack_id] = true
	return true

func _get_attack_id(hit_data: HitData) -> int:
	if hit_data.attack_id > 0:
		return hit_data.attack_id

	return hit_data.get_instance_id()
