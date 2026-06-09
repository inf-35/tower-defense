extends EffectPrototype
class_name SpinningTopEffect

@export var damage_bonus_per_attack: float = 0.05

class SpinningTopState extends RefCounted:
	var tower_modifiers: Dictionary[Tower, Modifier] = {}
	var tower_attacks: Dictionary[Tower, int] = {}
	var seen_attack_ids: Dictionary[int, bool] = {}

func _init() -> void:
	event_hooks = [
		GameEvent.EventType.PRE_HIT_DEALT,
		GameEvent.EventType.WAVE_PREP_STARTED,
		GameEvent.EventType.WAVE_STARTED,
		GameEvent.EventType.WAVE_ENDED,
		GameEvent.EventType.DIED,
	]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = SpinningTopState.new()
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(instance: EffectInstance) -> void:
	var state: SpinningTopState = instance.state as SpinningTopState
	for tower: Tower in state.tower_modifiers:
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			tower.modifiers_component.remove_modifier(state.tower_modifiers[tower])

	state.tower_modifiers.clear()
	state.tower_attacks.clear()
	state.seen_attack_ids.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	match event.event_type:
		GameEvent.EventType.PRE_HIT_DEALT:
			_handle_tower_attack(instance, event)
		GameEvent.EventType.WAVE_PREP_STARTED, GameEvent.EventType.WAVE_STARTED:
			_clear_wave_modifiers(instance)
		GameEvent.EventType.WAVE_ENDED:
			_clear_wave_modifiers(instance)
		GameEvent.EventType.DIED:
			_prune_dead_tower(instance, event)

func _handle_tower_attack(instance: EffectInstance, event: GameEvent) -> void:
	if Run.phases.current_phase != Run.phases.GamePhase.COMBAT_WAVE:
		return

	var tower: Tower = event.unit as Tower
	if not _is_valid_tower(tower):
		return

	var state: SpinningTopState = instance.state as SpinningTopState
	var hit_data: HitData = event.data as HitData
	if not HitData.consume_attack_id(hit_data, state.seen_attack_ids):
		return

	var attacks: int = state.tower_attacks.get(tower, 0) + 1
	state.tower_attacks[tower] = attacks

	var modifier: Modifier = state.tower_modifiers.get(tower, null) as Modifier
	if not is_instance_valid(modifier):
		modifier = Modifier.new(Attributes.id.DAMAGE)
		state.tower_modifiers[tower] = modifier
		tower.modifiers_component.add_modifier(modifier)

	modifier.multiplicative = 1.0 + (attacks * damage_bonus_per_attack * _get_effect_stacks(instance))
	tower.modifiers_component.change_modifier(modifier)

func _clear_wave_modifiers(instance: EffectInstance) -> void:
	var state: SpinningTopState = instance.state as SpinningTopState
	for tower: Tower in state.tower_modifiers:
		if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
			tower.modifiers_component.remove_modifier(state.tower_modifiers[tower])

	state.tower_modifiers.clear()
	state.tower_attacks.clear()
	state.seen_attack_ids.clear()

func _prune_dead_tower(instance: EffectInstance, event: GameEvent) -> void:
	var tower: Tower = event.unit as Tower
	if not is_instance_valid(tower):
		return

	var state: SpinningTopState = instance.state as SpinningTopState
	if state.tower_modifiers.has(tower) and is_instance_valid(tower.modifiers_component):
		tower.modifiers_component.remove_modifier(state.tower_modifiers[tower])

	state.tower_modifiers.erase(tower)
	state.tower_attacks.erase(tower)

func _is_valid_tower(tower: Tower) -> bool:
	if not is_instance_valid(tower):
		return false

	if tower.hostile or tower.environmental or tower.abstractive:
		return false

	if not is_instance_valid(tower.modifiers_component):
		return false

	return true

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)
