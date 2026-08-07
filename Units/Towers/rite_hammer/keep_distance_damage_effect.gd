extends EffectPrototype
class_name KeepDistanceDamageEffect

@export var max_bonus_multiplier: float = 0.7 ##extra damage at the keep
@export var falloff_per_tile: float = 0.07 ##extra damage removed per tile away from the keep
@export var tile_world_size: float = 10.0 ##world units treated as one tile for distance falloff

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##scales outgoing damage by how close the target is to the keep
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data or hit_data.negate:
		return
	if not is_instance_valid(hit_data.target):
		return

	var keep_position: Vector2 = _get_keep_position()
	var distance_tiles: float = hit_data.target.global_position.distance_to(keep_position) / maxf(tile_world_size, 0.001)
	var stack_count: float = maxf(float(instance.stacks), 1.0)
	var bonus_multiplier: float = maxf(max_bonus_multiplier - distance_tiles * falloff_per_tile, 0.0) * stack_count
	if bonus_multiplier <= 0.0:
		return

	hit_data.damage *= 1.0 + bonus_multiplier
	trigger_source_tower_pulse(instance)

func _get_keep_position() -> Vector2:
	if is_instance_valid(Run.references.keep) and Run.references.keep is Node2D:
		return (Run.references.keep as Node2D).global_position

	return Island.cell_to_position(Vector2i.ZERO)
