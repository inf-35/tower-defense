extends EffectPrototype
class_name LodestoneRiteEffect

const LINEAGE_PRODUCER_LABEL: StringName = &"lodestone_rite_effect"

@export var split_count: int = 3 ##total prioritized targets considered for each affected targeted attack
@export var damage_multiplier: float = 0.33 ##damage retained by each split part
@export var split_delay_cooldown_fraction: float = 0.1 ##game-time delay between split parts as a fraction of the source tower's current cooldown
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
	if not hit_data.mark_lineage_producer_label(LINEAGE_PRODUCER_LABEL):
		return

	var source_tower: Tower = event.unit as Tower
	var targets: Array[Unit] = _get_split_targets(source_tower, hit_data.target)
	if targets.is_empty():
		return

	hit_data.damage *= damage_multiplier
	var split_delay: float = _get_split_delay(source_tower)
	for i: int in range(1, targets.size()):
		_fire_delayed_sibling_attack(source_tower, targets[i], hit_data, split_delay * float(i))

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
	if hit_data.has_lineage_producer_label(LINEAGE_PRODUCER_LABEL):
		return false
	if not is_instance_valid(hit_data.target):
		return false
	return split_count > 1 and damage_multiplier > 0.0

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

func _get_split_delay(source_tower: Tower) -> float: ##returns the authored inter-part delay using the tower's current modified attack cooldown
	if not is_instance_valid(source_tower) or not is_instance_valid(source_tower.attack_component):
		return 0.0

	return maxf(source_tower.attack_component.cooldown * split_delay_cooldown_fraction, 0.0)

func _fire_delayed_sibling_attack(source_tower: Tower, target: Unit, parent_hit_data: HitData, delay: float) -> void: ##fires one lodestone sibling after a game-time delay while rechecking runtime validity
	if delay > 0.0:
		await Clock.await_game_time(delay)

	if not is_instance_valid(source_tower) or not is_instance_valid(source_tower.attack_component):
		return
	if not is_instance_valid(target) or not is_instance_valid(parent_hit_data):
		return

	source_tower.attack_component.fire_sibling_attack(target, parent_hit_data, damage_multiplier)
