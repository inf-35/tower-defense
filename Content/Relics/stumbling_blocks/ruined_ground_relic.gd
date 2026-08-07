extends EffectPrototype
class_name RuinedGroundEffect

@export var modifier_prototype: ModifierDataPrototype
@export var damage_taken_modifier_prototype: ModifierDataPrototype

class RuinedGroundState extends RefCounted:
	var affected_units: Dictionary[Unit, Array] = {}

func _init() -> void:
	#we listen for cell changes (movement) and death (cleanup)
	event_hooks = [GameEvent.EventType.CHANGED_CELL, GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = RuinedGroundState.new()
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	#waiting for movement is sufficient
	pass

func _handle_detach(instance: EffectInstance) -> void:
	var state: RuinedGroundState = instance.state as RuinedGroundState
	var affected_units: Array[Unit] = []
	affected_units.assign(state.affected_units.keys())

	for unit: Unit in affected_units:
		_remove_modifiers(state, unit)

	state.affected_units.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	var state: RuinedGroundState = instance.state as RuinedGroundState
	var unit: Unit = event.unit

	#cleanup handler
	if event.event_type == GameEvent.EventType.DIED:
		_remove_modifiers(state, unit)
		return

	#movement handler
	if event.event_type == GameEvent.EventType.CHANGED_CELL:
		#validation
		if not is_instance_valid(unit):
			return

		var data: ChangedCellData = event.data as ChangedCellData
		_evaluate_unit_position(state, unit, data.new_cell)

func _evaluate_unit_position(state: RuinedGroundState, unit: Unit, cell: Vector2i) -> void:
	var is_on_ruin: bool = Run.player.ruin_service.is_cell_ruined(cell)
	var is_currently_affected: bool = state.affected_units.has(unit)

	#entered ruins (apply)
	if is_on_ruin and not is_currently_affected:
		_apply_modifiers(state, unit)
		return

	#left ruins (remove)
	if (not is_on_ruin) and is_currently_affected:
		_remove_modifiers(state, unit)

func _apply_modifiers(state: RuinedGroundState, unit: Unit) -> void:
	if not is_instance_valid(unit) or not is_instance_valid(unit.modifiers_component):
		return

	var modifiers: Array[Modifier] = []
	_add_modifier_from_prototype(unit, modifiers, modifier_prototype)
	_add_modifier_from_prototype(unit, modifiers, damage_taken_modifier_prototype)
	if modifiers.is_empty():
		return

	state.affected_units[unit] = modifiers

func _add_modifier_from_prototype(unit: Unit, modifiers: Array[Modifier], prototype: ModifierDataPrototype) -> void:
	if not is_instance_valid(prototype):
		return

	var modifier: Modifier = prototype.generate_modifier()
	modifier.cooldown = -1.0
	unit.modifiers_component.add_modifier(modifier)
	modifiers.append(modifier)

func _remove_modifiers(state: RuinedGroundState, unit: Unit) -> void:
	if not state.affected_units.has(unit):
		return

	if is_instance_valid(unit) and is_instance_valid(unit.modifiers_component):
		var modifiers: Array = state.affected_units[unit]
		for modifier: Modifier in modifiers:
			if is_instance_valid(modifier):
				unit.modifiers_component.remove_modifier(modifier)

	state.affected_units.erase(unit)
