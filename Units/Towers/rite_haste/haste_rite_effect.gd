extends EffectPrototype
class_name HasteRiteEffect

@export var buff_modifier: ModifierDataPrototype ##e.g., +50% range, +300% fire rate (0.25 cooldown)
@export var self_damage: float = 0.1

class HasteState extends RefCounted:
	var modifier: Modifier
	var seen_attack_ids: Dictionary[int, bool] = {}

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var i := EffectInstance.new()
	apply_generics(i)
	i.state = HasteState.new()
	return i

func _handle_attach(instance: EffectInstance) -> void:
	var state: HasteState = instance.state as HasteState
	var tower: Tower = instance.host as Tower

	if is_instance_valid(tower) and buff_modifier:
		var mod := buff_modifier.generate_modifier()
		mod.stack(instance.stacks)
		tower.modifiers_component.add_modifier(mod)
		state.modifier = mod

func _handle_stack_update(instance: EffectInstance) -> void:
	_handle_detach(instance)
	_handle_attach(instance)

func _handle_detach(instance: EffectInstance) -> void:
	var state: HasteState = instance.state as HasteState
	if state.modifier and is_instance_valid(instance.host) and is_instance_valid(instance.host.modifiers_component):
		instance.host.modifiers_component.remove_modifier(state.modifier)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	var state: HasteState = instance.state as HasteState
	if not HitData.consume_attack_id(hit_data, state.seen_attack_ids):
		return

	var tower: Tower = instance.host as Tower
	if not is_instance_valid(tower):
		return

	#deal self-damage
	for i in instance.stacks:
		var hit := HitData.new()
		hit.damage = self_damage
		hit.source = tower
		hit.target = tower
		hit.target_affiliation = tower.hostile #matches self affiliation
		if not hit.derive_lineage_from(hit_data, instance):
			continue

		#apply directly so it mitigates through standard defensive layers
		tower.take_hit(hit)

	trigger_source_tower_pulse(instance)
