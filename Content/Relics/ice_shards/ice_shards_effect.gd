extends EffectPrototype
class_name IceShardsEffect

@export var shard_count: int = 3
@export var spread_angle: float = 45.0 ## the cone width behind the enemy
@export var damage_multiplier: float = 0.1 ## taken from the dead enemy's HP
@export var required_status: Attributes.Status = Attributes.Status.FROST
@export var attack_data: AttackData ## defines the single Shard projectile

func _init() -> void:
	# Trigger on death, requires HitReportData for direction
	event_hooks = [GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_i: EffectInstance) -> void: pass
func _handle_detach(_i: EffectInstance) -> void: pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dead_unit: Unit = event.unit
	var report := event.data as HitReportData
	
	if not is_instance_valid(dead_unit) or not report:
		return
		
	# 2. Check Status Condition
	if not is_instance_valid(dead_unit.modifiers_component):
		return
	if not dead_unit.modifiers_component.has_status(required_status):
		return
	
	# 4. Spawn Shards
	_spawn_shards(dead_unit, report.source, report.velocity)

func _spawn_shards(center_unit: Unit, source: Unit, velocity: Vector2) -> void:
	if attack_data == null: return
	
	var start_pos = center_unit.global_position
	var base_angle = velocity.angle()
	var half_spread = deg_to_rad(spread_angle * 0.5)
	if velocity.is_zero_approx(): #probably a blank hit report (death from status, etc.), so just do a 360deg blast
		half_spread = PI
		base_angle = randf_range(-PI, PI)
	
	for i in shard_count:
		# Calculate cone spread
		# e.g. for 3 shards: -angle, 0, +angle
		var offset_angle: float = lerpf(-half_spread, half_spread, float(i) / max(1, shard_count - 1))
		var final_dir: Vector2 = Vector2.from_angle(base_angle + offset_angle)

		var hit_data := attack_data.generate_generic_hit_data()
		hit_data.source = source
		hit_data.damage = center_unit.get_stat(Attributes.id.MAX_HEALTH) * damage_multiplier
		hit_data.target = null # untargeted projectile
		hit_data.target_affiliation = center_unit.hostile

		var delivery := attack_data.generate_generic_delivery_data()
		delivery.delivery_method = DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED
		delivery.excluded_units = [center_unit]
		
		delivery.use_source_position_override = true
		delivery.source_position = start_pos
		
		delivery.use_initial_velocity_override = true
		delivery.initial_velocity = final_dir * attack_data.projectile_speed

		CombatManager.resolve_hit(hit_data, delivery)
