extends EffectPrototype
class_name StatusInfusionEffect

@export var status: Attributes.Status = Attributes.Status.FROST
@export var bonus_stacks: float = 1.0
@export var bonus_time: float = 2.0
@export var projectile_tint: Color = Color(0.5803922, 0.8980392, 1.0, 1.0) ##tint appended to the projectile palette so multi-rite attacks can cycle between distinct colors instead of blending them

func _init() -> void:
	#intercept hits before they leave the tower
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data:
		return

	var status_vector: Vector2 = hit_data.status_effects.get(status, Vector2.ZERO)

	status_vector.x += bonus_stacks * instance.stacks
	status_vector.y = maxf(status_vector.y, bonus_time)

	hit_data.status_effects[status] = status_vector
	append_projectile_tint(hit_data, projectile_tint)
	trigger_source_tower_pulse(instance)
