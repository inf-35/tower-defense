extends EffectPrototype
class_name PawnStructureLocalEffect ##local effect

@export var damage_bonus: float = 0.20
@export var target_type: Towers.Type = Towers.Type.TURRET

class PawnState extends RefCounted:
	var modifier: Modifier
	
#implementation NOTE: TOWER_BUILT signals by default do not (and shldnt) propagate
#to the local layer, so we directly proc our relevant neighbours

func _init() -> void:
	event_hooks = []

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	i.state = PawnState.new()
	return i

func _handle_attach(instance: EffectInstance) -> void:
	if instance.host is Tower:
		_evaluate(instance, true)

func _handle_detach(instance: EffectInstance) -> void:
	var state = instance.state as PawnState
	if state.modifier:
		instance.host.modifiers_component.remove_modifier(state.modifier)
	state.modifier = null

	var towers: Array[Tower] = instance.host.get_diagonal_towers().values()
	await References.root.get_tree().process_frame
	#proc relevant towers to update (can only be done after one frame -> when the tower disappears)
	for n: Tower in towers:
		if is_instance_valid(n) and n.type == target_type:
			var effect_instance := n.get_effect_instance_by_prototype(self)
			if effect_instance:
				effect_instance.handle_event_unfiltered()

func _handle_event(instance: EffectInstance, event: GameEvent = null) -> void:
	if instance.host is Tower:
		_evaluate(instance)

func _evaluate(instance: EffectInstance, is_being_built: bool = false) -> void:
	var tower = instance.host as Tower
	if not is_instance_valid(tower): return
	
	var neighbors = tower.get_diagonal_towers()
	var stacks = 0
	
	for n: Tower in neighbors.values():
		if is_instance_valid(n) and n.type == target_type and (not n.disabled) and (not n.is_queued_for_deletion()):
			stacks += 1
			
	if is_being_built: #proc relevant towers to also update
		for n: Tower in neighbors.values():
			if is_instance_valid(n) and n.type == target_type:
				var effect_instance := n.get_effect_instance_by_prototype(self)
				if effect_instance:
					effect_instance.handle_event_unfiltered()

	var state = instance.state as PawnState
	var desired_mult = 1.0 + (stacks * damage_bonus)
	
	if stacks > 0:
		if state.modifier:
			state.modifier.multiplicative = desired_mult
			tower.modifiers_component.change_modifier(state.modifier)
		else:
			var mod = Modifier.new(Attributes.id.DAMAGE, desired_mult, 0.0, -1.0)
			tower.modifiers_component.add_modifier(mod)
			state.modifier = mod
	else:
		if state.modifier:
			tower.modifiers_component.remove_modifier(state.modifier)
			state.modifier = null
