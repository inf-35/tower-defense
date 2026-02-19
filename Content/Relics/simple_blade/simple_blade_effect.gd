extends EffectPrototype
class_name SimpleBladeEffect

@export var bonus_per_tower: float = 0.03 ## +3% per tower

# State: Maps each tower to the specific modifier instance we gave it
class BladeState extends RefCounted:
	var tower_modifiers: Dictionary[Tower, Modifier] = {}

func _init() -> void:
	event_hooks = [GameEvent.EventType.TOWER_BUILT, GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	i.state = BladeState.new()
	return i

func _handle_attach(instance: EffectInstance) -> void:
	_recalculate_all(instance)

func _handle_detach(instance: EffectInstance) -> void:
	var state = instance.state as BladeState
	for t in state.tower_modifiers:
		if is_instance_valid(t) and t.modifiers_component:
			t.modifiers_component.remove_modifier(state.tower_modifiers[t])
	state.tower_modifiers.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type == GameEvent.EventType.TOWER_BUILT:
		_recalculate_all(instance)
		if (not event.data.tower.hostile) and (not event.data.tower.environmental):
			UI.floating_text_manager.show_icon(icon, event.data.tower.global_position)
	elif event.event_type == GameEvent.EventType.DIED:
		if event.unit is Tower:
			_recalculate_all(instance)

func _recalculate_all(instance: EffectInstance) -> void:
	var state = instance.state as BladeState
	var all_towers = References.island.get_tree().get_nodes_in_group(References.TOWER_GROUP)
	var tower_count = 0
	for tower: Tower in all_towers:
		if tower.hostile:
			continue
		
		if tower.environmental:
			continue
		
		if tower.is_queued_for_deletion():
			continue
			
		tower_count += 1
	
	var multiplier = 1.0 + (tower_count * bonus_per_tower)
	for t: Tower in all_towers:
		if not is_instance_valid(t.modifiers_component): continue
		
		if state.tower_modifiers.has(t):
			var mod = state.tower_modifiers[t]
			if not is_equal_approx(mod.multiplicative, multiplier):
				mod.multiplicative = multiplier
				t.modifiers_component.change_modifier(mod)
		else:
			# Add new
			var mod = Modifier.new(Attributes.id.DAMAGE, multiplier, 0.0, -1.0)
			t.modifiers_component.add_modifier(mod)
			state.tower_modifiers[t] = mod
