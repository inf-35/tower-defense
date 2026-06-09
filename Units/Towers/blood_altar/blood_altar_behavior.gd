extends Behavior
class_name BloodAltarBehavior

@export var structure_damage: float = 1.0 ##damage dealt to each adjacent allied structure as the altar primes itself
@export_range(0.0, 1.0, 0.01) var projectile_interval_proportion: float = 0.1 ##share of total cooldown spent spacing the follow-up projectiles

var _is_firing_sequence: bool = false

func update(_delta: float) -> void: ##starts a staggered volley once a valid target exists and the altar is idle
	if _is_firing_sequence:
		return

	if not _is_attack_possible():
		return

	var target: Unit = range_component.get_target()
	if not is_instance_valid(target):
		return

	_start_attack_sequence(target)

func _start_attack_sequence(target: Unit) -> void: ##consumes one attack context and reuses it across the self-damage and projectile volley
	var attack_id: int = AttackComponent.get_next_attack_id()
	var attack_context: AttackComponent.AttackLineageContext = attack_component.pull_attack_context()
	if not is_instance_valid(attack_context):
		return

	var damaged_structure_positions: Array[Vector2] = _damage_adjacent_structures(attack_id, attack_context)
	if damaged_structure_positions.is_empty():
		attack_component.refresh_cooldown()
		return

	_is_firing_sequence = true
	attack_component.refresh_cooldown()
	_play_animation(&"attack")

	var interval: float = attack_component.cooldown * projectile_interval_proportion
	for source_position: Vector2 in damaged_structure_positions:
		if not is_instance_valid(target) or unit.disabled:
			break

		_fire_projectile(target, source_position, attack_id, attack_context)
		if interval > 0.0:
			await Clock.await_game_time(interval)

	_is_firing_sequence = false

func _damage_adjacent_structures(attack_id: int, attack_context: AttackComponent.AttackLineageContext) -> Array[Vector2]: ##applies the priming self-damage once per adjacent allied structure and returns the successful launch points
	var tower: Tower = unit as Tower
	var damaged_structure_positions: Array[Vector2] = []
	if not is_instance_valid(tower):
		return damaged_structure_positions

	var adjacent_towers: Dictionary[Vector2i, Tower] = tower.get_adjacent_towers()
	var adjacent_values: Array = adjacent_towers.values()
	for value: Variant in adjacent_values:
		var adjacent_tower: Tower = value as Tower
		if not _can_damage_structure(adjacent_tower):
			continue

		var health_before: float = adjacent_tower.health_component.health
		var structure_hit: HitData = _create_structure_hit(adjacent_tower, attack_id, attack_context)
		if not is_instance_valid(structure_hit):
			continue

		adjacent_tower.take_hit(structure_hit)
		if adjacent_tower.health_component.health < health_before:
			damaged_structure_positions.append(adjacent_tower.global_position)

	return damaged_structure_positions

func _can_damage_structure(candidate: Tower) -> bool: ##filters to adjacent living allied structures that the altar is allowed to hurt
	if not is_instance_valid(candidate):
		return false

	if candidate == unit or candidate.hostile:
		return false

	if candidate.current_state != Tower.State.ACTIVE:
		return false

	if not is_instance_valid(candidate.health_component):
		return false

	if candidate.health_component.health <= 0.0:
		return false

	return true

func _create_structure_hit(target: Tower, attack_id: int, attack_context: AttackComponent.AttackLineageContext) -> HitData: ##builds the internal self-damage hit so it shares the same logical attack family as the volley
	var hit_data: HitData = HitData.new()
	hit_data.source = unit
	hit_data.target = target
	hit_data.target_affiliation = target.hostile
	hit_data.damage = structure_damage
	hit_data.breaking = true
	hit_data.attack_id = attack_id
	hit_data.velocity = (target.global_position - unit.global_position).normalized()
	if not attack_component.apply_attack_context(hit_data, attack_context):
		return null

	return hit_data

func _fire_projectile(target: Unit, source_position: Vector2, attack_id: int, attack_context: AttackComponent.AttackLineageContext) -> void: ##fires one projectile that inherits the shared lineage stamp for this altar attack
	var delivery_data: DeliveryData = attack_component.generate_delivery_data()
	delivery_data.target = target
	delivery_data.use_source_position_override = true
	delivery_data.source_position = source_position
	delivery_data.intercept_position = AttackComponent.predict_intercept_position(unit, target, delivery_data.projectile_speed)

	var hit_data: HitData = attack_component.generate_hit_data(delivery_data)
	hit_data.target = target
	hit_data.target_affiliation = target.hostile
	hit_data.attack_id = attack_id
	if not attack_component.apply_attack_context(hit_data, attack_context):
		return

	unit.deal_hit(hit_data, delivery_data)

func draw_visuals(canvas: RangeIndicator) -> void: ##shows the tower range plus the adjacent structures it can siphon
	super.draw_visuals(canvas)
	draw_visuals_adjacent_tiles(canvas)
