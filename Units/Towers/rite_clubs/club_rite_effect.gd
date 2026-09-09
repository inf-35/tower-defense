extends EffectPrototype
class_name ClubRiteEffect

class ClubRiteState extends RefCounted:
	var seen_attack_ids: Dictionary[int, bool] = {}
	var stun_attack_ids: Dictionary[int, bool] = {}
	var feedback_attack_ids: Dictionary[int, bool] = {}
	var attack_counter: int = 0

@export var attacks_required: int = 4 ##unique attacks from each affected tower required before stun is applied
@export var minimum_trigger_damage: float = 2.0 ##attack damage must exceed this value before clubs counts the attack
@export var duration: float = 2.0 ##stun duration applied on the qualifying attack

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = ClubRiteState.new()
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not _is_qualifying_hit(hit_data):
		return

	var state: ClubRiteState = instance.state as ClubRiteState
	if not state:
		return

	if not state.seen_attack_ids.has(hit_data.attack_id):
		state.seen_attack_ids[hit_data.attack_id] = true
		state.attack_counter += 1
		if state.attack_counter >= maxi(attacks_required, 1):
			state.attack_counter = 0
			state.stun_attack_ids[hit_data.attack_id] = true

	if not state.stun_attack_ids.has(hit_data.attack_id):
		return

	hit_data.status_effects[Attributes.Status.STUN] = Vector2(1.0, duration)
	if not state.feedback_attack_ids.has(hit_data.attack_id):
		state.feedback_attack_ids[hit_data.attack_id] = true
		trigger_source_tower_pulse(instance)

func _is_qualifying_hit(hit_data: HitData) -> bool:
	if not hit_data:
		return false
	if not hit_data.primary:
		return false
	if hit_data.negate:
		return false
	if hit_data.attack_id <= 0:
		return false
	return hit_data.damage > minimum_trigger_damage
