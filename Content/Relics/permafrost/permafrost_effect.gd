extends EffectPrototype
class_name PermafrostEffect

@export var extra_status: Attributes.Status = Attributes.Status.FROST
@export var extra_stacks: float = 1.0
@export var target_element: Towers.Element = Towers.Element.FROST

func _init() -> void:
	# PRE_HIT_DEALT allows us to modify HitData before it is processed by the target
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return
	
	# check source element
	var source_unit: Unit = event.unit
	if not is_instance_valid(source_unit) or not source_unit is Tower:
		return
	if Towers.get_tower_element(source_unit.type) != target_element:
		return

	var hit_data := event.data as HitData # modify hit data
	if not hit_data:
		return

	var current_data: Vector2 = hit_data.status_effects[extra_status] if hit_data.status_effects.has(extra_status) else Vector2(0.0, 1.0)
	# x = stacks, y = duration (if no existing effect exists, default to 1 second as duration)
	current_data.x += extra_stacks
	hit_data.status_effects[extra_status] = current_data
