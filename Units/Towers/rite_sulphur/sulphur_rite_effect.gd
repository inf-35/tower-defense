extends EffectPrototype
class_name SulphurRiteEffect

class SulphurRiteState extends RefCounted:
	var damage_modifier: Modifier
	var cooldown_modifier: Modifier
	var radius_modifier: Modifier

@export var damage_multiplier: float = 0.5 ##damage multiplier applied to affected towers
@export var cooldown_multiplier: float = 2.0 ##cooldown multiplier applied to affected towers; 2.0 means half hitrate
@export var radius_bonus: float = 10.0 ##flat aoe radius bonus per overlapping sulphur rite

func _init() -> void:
	event_hooks = [GameEvent.EventType.NONE]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = SulphurRiteState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	_apply_modifiers(instance)

func _handle_detach(instance: EffectInstance) -> void:
	_remove_modifiers(instance)

func _handle_stack_update(instance: EffectInstance) -> void:
	_remove_modifiers(instance)
	_apply_modifiers(instance)

func _handle_event(_instance: EffectInstance, _event: GameEvent) -> void:
	pass

func _apply_modifiers(instance: EffectInstance) -> void:
	var tower: Tower = instance.host as Tower
	if not is_instance_valid(tower) or not is_instance_valid(tower.modifiers_component):
		return

	var state: SulphurRiteState = instance.state as SulphurRiteState
	if not state:
		return

	var stacks: int = maxi(instance.stacks, 1)
	state.damage_modifier = Modifier.new(Attributes.id.DAMAGE, pow(damage_multiplier, stacks), 0.0, -1.0, null, instance.source_id)
	state.cooldown_modifier = Modifier.new(Attributes.id.COOLDOWN, pow(cooldown_multiplier, stacks), 0.0, -1.0, null, instance.source_id)
	state.radius_modifier = Modifier.new(Attributes.id.RADIUS, 1.0, radius_bonus * stacks, -1.0, null, instance.source_id)

	tower.modifiers_component.add_modifier(state.damage_modifier)
	tower.modifiers_component.add_modifier(state.cooldown_modifier)
	tower.modifiers_component.add_modifier(state.radius_modifier)

func _remove_modifiers(instance: EffectInstance) -> void:
	var tower: Tower = instance.host as Tower
	if not is_instance_valid(tower) or not is_instance_valid(tower.modifiers_component):
		return

	var state: SulphurRiteState = instance.state as SulphurRiteState
	if not state:
		return

	_remove_modifier(tower, state.damage_modifier)
	_remove_modifier(tower, state.cooldown_modifier)
	_remove_modifier(tower, state.radius_modifier)
	state.damage_modifier = null
	state.cooldown_modifier = null
	state.radius_modifier = null

func _remove_modifier(tower: Tower, modifier: Modifier) -> void:
	if is_instance_valid(modifier):
		tower.modifiers_component.remove_modifier(modifier)
