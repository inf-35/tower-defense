extends EffectPrototype
class_name WallflowerEffect

# --- Configuration ---
@export var modifier_prototype: ModifierDataPrototype

# --- State ---
class WallflowerState extends RefCounted:
	var modifier: Modifier

func _init() -> void:
	# Recalculate on grid changes
	event_hooks = [GameEvent.EventType.ADJACENCY_UPDATED]

func create_instance() -> EffectInstance:
	var i := EffectInstance.new()
	apply_generics(i)
	i.state = WallflowerState.new()
	return i

func _handle_attach(instance: EffectInstance) -> void:
	if instance.host is Tower:
		_evaluate(instance)

func _handle_detach(instance: EffectInstance) -> void:
	var state = instance.state as WallflowerState
	if state.modifier and is_instance_valid(instance.host.modifiers_component):
		instance.host.modifiers_component.remove_modifier(state.modifier)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.unit == instance.host:
		_evaluate(instance)

func _evaluate(instance: EffectInstance) -> void:
	var tower = instance.host as Tower
	if not is_instance_valid(tower): return

	var neighbors = tower.get_adjacent_towers()
	var has_neighbors = not neighbors.is_empty()
	
	var state = instance.state as WallflowerState
	
	if not has_neighbors:
		if not state.modifier:
			UI.floating_text_manager.show_icon(icon, tower.global_position)
			var mod := modifier_prototype.generate_modifier()
			tower.modifiers_component.add_modifier(mod)
			state.modifier = mod
	else:
		# remove buff (condition failed)
		if state.modifier:
			tower.modifiers_component.remove_modifier(state.modifier)
			state.modifier = null
