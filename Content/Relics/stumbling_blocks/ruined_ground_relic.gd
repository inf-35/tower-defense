extends EffectPrototype
class_name RuinedGroundEffect

@export var modifier_prototype: ModifierDataPrototype

# track which unit has which specific modifier instance so we can remove it later
class RuinedGroundState extends RefCounted:
	var slowed_units: Dictionary[Unit, Modifier] = {}

func _init() -> void:
	# We listen for cell changes (movement) and death (cleanup)
	event_hooks = [GameEvent.EventType.CHANGED_CELL, GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = RuinedGroundState.new()
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	# waiting for movement is sufficient
	pass

func _handle_detach(instance: EffectInstance) -> void:
	var state := instance.state as RuinedGroundState
	
	# clean up: remove effect from everyone if the relic is lost/sold
	for unit: Unit in state.slowed_units:
		if is_instance_valid(unit) and is_instance_valid(unit.modifiers_component):
			var mod: Modifier = state.slowed_units[unit]
			unit.modifiers_component.remove_modifier(mod)

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	var state := instance.state as RuinedGroundState
	var unit: Unit = event.unit

	# cleanup handler
	if event.event_type == GameEvent.EventType.DIED:
		if state.slowed_units.has(unit):
			state.slowed_units.erase(unit)
		return

	# movement handler
	if event.event_type == GameEvent.EventType.CHANGED_CELL:
		# validation
		if not is_instance_valid(unit):
			return
			
		var data := event.data as ChangedCellData
		_evaluate_unit_position(state, unit, data.new_cell)

func _evaluate_unit_position(state: RuinedGroundState, unit: Unit, cell: Vector2i) -> void:
	var is_on_ruin: bool = Player.ruin_service.is_cell_ruined(cell)
	var is_currently_slowed: bool = state.slowed_units.has(unit)
	
	# entered ruins (apply)
	if is_on_ruin and not is_currently_slowed:
		if is_instance_valid(unit.modifiers_component):
			var mod: Modifier = modifier_prototype.generate_modifier()
			mod.cooldown = -1.0 # permanent until manually removed
			
			unit.modifiers_component.add_modifier(mod)
			state.slowed_units[unit] = mod
			
	# left ruins (remove)
	elif not is_on_ruin and is_currently_slowed:
		if is_instance_valid(unit.modifiers_component):
			var mod: Modifier = state.slowed_units[unit]
			unit.modifiers_component.remove_modifier(mod)
		
		state.slowed_units.erase(unit)
