extends EffectPrototype
class_name LodestoneRiteEffect

@export var split_count: int = 3 ##total prioritized targets considered for each affected primary attack
@export var damage_multiplier: float = 0.33 ##damage retained by each split part
@export var excluded_tower_types: Array[Towers.Type] = [Towers.Type.PRISM] ##spatial attack models that do not expose a normal prioritized target attack

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

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##turns one targeted attack payload into a three-part volley with independently procable siblings
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not _can_split(instance, event.unit as Tower, hit_data):
		return
	if not hit_data.mark_lineage_producer(_get_lineage_producer()):
		return

	var source_tower: Tower = event.unit as Tower
	var targets: Array[Unit] = _get_split_targets(source_tower, hit_data.target)
	if targets.is_empty():
		return

	hit_data.damage *= damage_multiplier
	for i: int in range(1, targets.size()):
		source_tower.attack_component.call_deferred(
			&"fire_sibling_attack",
			targets[i],
			hit_data,
			damage_multiplier
		)

	if targets.size() > 1:
		trigger_source_tower_pulse(instance)

func _can_split(instance: EffectInstance, source_tower: Tower, hit_data: HitData) -> bool:
	if not is_instance_valid(source_tower) or source_tower != instance.host:
		return false
	if excluded_tower_types.has(source_tower.type):
		return false
	if not is_instance_valid(source_tower.attack_component) or not is_instance_valid(source_tower.range_component):
		return false
	if not is_instance_valid(hit_data) or hit_data.negate:
		return false
	if hit_data.has_lineage_producer(_get_lineage_producer()):
		return false
	if not is_instance_valid(hit_data.target):
		return false
	return split_count > 1 and damage_multiplier > 0.0

func _get_lineage_producer() -> Object:
	var script: Script = get_script() as Script
	if is_instance_valid(script):
		return script
	return self

func _get_split_targets(source_tower: Tower, primary_target: Unit) -> Array[Unit]:
	var targets: Array[Unit] = []
	if not is_instance_valid(primary_target):
		return targets

	targets.append(primary_target)
	var prioritized_targets: Array[Unit] = source_tower.range_component.get_targets(split_count)
	for target: Unit in prioritized_targets:
		if targets.size() >= split_count:
			break
		if not is_instance_valid(target) or targets.has(target):
			continue
		targets.append(target)

	return targets
