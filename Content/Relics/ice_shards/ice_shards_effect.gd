extends EffectPrototype
class_name IceShardsEffect

@export var shard_count: int = 3 ##number of simulated shards released by each qualifying death
@export var spread_angle: float = 45.0 ##the cone width behind the enemy
@export var damage_multiplier: float = 0.1 ##taken from the dead enemy's hp
@export var required_status: Attributes.Status = Attributes.Status.FROST ##status required on the enemy when it dies
@export var attack_data: AttackData ##defines the single shard projectile

func _init() -> void: ##registers ice shards as a global enemy-death reaction
	event_hooks = [GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance: ##creates a stateless global effect instance
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##shatters a frozen enemy into simulated projectiles using its death-hit direction
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dead_unit: Unit = event.unit
	var report: HitReportData = event.data as HitReportData
	if not is_instance_valid(dead_unit) or not dead_unit.hostile or not report:
		return

	if not is_instance_valid(dead_unit.modifiers_component):
		return
	if not dead_unit.modifiers_component.has_status(required_status):
		return
	if attack_data == null:
		push_warning("IceShardsEffect: triggered but no attack_data assigned.")
		return

	_spawn_shards(instance, report, dead_unit)

func _spawn_shards(instance: EffectInstance, parent_report: HitReportData, center_unit: Unit) -> void: ##fans lineage-derived shards away from the killing hit, or radially when it has no direction
	var start_position: Vector2 = center_unit.global_position
	var velocity: Vector2 = parent_report.velocity
	var base_angle: float = velocity.angle()
	var half_spread: float = deg_to_rad(spread_angle * 0.5)
	if velocity.is_zero_approx():
		half_spread = PI
		base_angle = randf_range(-PI, PI)

	var safe_shard_count: int = maxi(shard_count, 1)
	var shard_damage: float = center_unit.get_stat(Attributes.id.MAX_HEALTH) * damage_multiplier
	for index: int in range(safe_shard_count):
		var spread_weight: float = float(index) / float(maxi(safe_shard_count - 1, 1))
		var offset_angle: float = lerpf(-half_spread, half_spread, spread_weight)
		var final_dir: Vector2 = Vector2.from_angle(base_angle + offset_angle)

		var hit_data := attack_data.generate_generic_hit_data()
		if not hit_data.derive_lineage_from(parent_report, instance):
			continue
		hit_data.source = parent_report.get_source_unit()
		hit_data.attack_id = AttackComponent.get_next_attack_id()
		hit_data.primary = false
		hit_data.damage = shard_damage
		hit_data.target = null
		hit_data.target_affiliation = center_unit.hostile

		var delivery: DeliveryData = attack_data.generate_generic_delivery_data()
		delivery.excluded_units = [center_unit]
		delivery.use_source_position_override = true
		delivery.source_position = start_position
		delivery.use_initial_velocity_override = true
		delivery.initial_velocity = final_dir * attack_data.projectile_speed

		CombatManager.resolve_hit(hit_data, delivery)
