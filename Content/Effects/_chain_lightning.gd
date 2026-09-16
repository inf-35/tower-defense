extends EffectPrototype
class_name ChainLightningEffect

@export var max_jumps: int = 3 ##maximum number of secondary targets the arc may chain through after the primary hit
@export var jump_radius: float = 150.0 ##search radius used to find the next nearest valid target after each jump
@export var damage_falloff_multiplier: float = 0.66 ##damage retained after each jump; values below one decay the chain
@export var status_cooldown_falloff_multiplier: float = 0.66 ##timed status duration retained after each jump; permanent statuses are unaffected
@export var show_jump_feedback: bool = true ##when true, each lightning segment draws a short-lived debug line so the full arc is visible
@export var jump_feedback_color: Color = Color(1.0, 0.9, 0.2, 0.45) ##debug line tint shared by the root strike and chained jumps
@export var jump_feedback_width: float = 3.0 ##debug line width used for the lightning overlay
@export var jump_feedback_duration: float = 0.18 ##seconds each debug line persists before it is cleaned up
@export var jump_particle_swirls: Array[VFXInfo] = [] ##authored swirl layers drawn underneath each visible lightning segment

func _init() -> void:
	#listen for when the host deals a hit
	event_hooks = [GameEvent.EventType.HIT_DEALT]

func create_instance() -> EffectInstance: ##creates a stateless reactive effect that piggybacks on the host's normal attacks
	var instance := EffectInstance.new()
	apply_generics(instance)
	#no persistent state required for chain lightning, so we don't assign instance.state
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	#reactive effect; no setup required
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	#reactive effect; no cleanup required
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##only roots off true attack payloads so derived effect hits do not restart the chain
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var hit_report: HitReportData = event.data as HitReportData
	if not is_instance_valid(hit_report.target) or hit_report.attack_id <= 0:
		return
	if hit_report.has_lineage_producer(instance):
		return

	#cast host to tower to access attack components
	var host_tower: Tower = instance.host as Tower
	if not is_instance_valid(host_tower) or not is_instance_valid(host_tower.attack_component):
		return

	_execute_chain_lightning(instance, host_tower, hit_report)

func _execute_chain_lightning(instance: EffectInstance, host: Tower, initial_report: HitReportData) -> void: ##walks chained hits through attack_component.attack so the attack pipeline still owns pre-hit mutation and delivery
	var target_hostile: bool = initial_report.target.hostile
	var target_position: Vector2 = initial_report.target.global_position
	var already_hit: Array[Unit] = [initial_report.target]

	_play_jump_feedback(_get_attack_origin(host), target_position)

	#calculate base damage from the tower's stats
	var current_damage: float = host.attack_component.get_stat(
		host.modifiers_component,
		host.attack_component.attack_data,
		Attributes.id.DAMAGE
	)
	var current_status_cooldown_multiplier: float = 1.0

	for i: int in range(max_jumps):
		#find a new target near the last one hit
		var next_target: Unit = _find_next_jump_target(target_position, target_hostile, jump_radius, already_hit)

		if not is_instance_valid(next_target):
			break

		current_damage *= damage_falloff_multiplier
		current_status_cooldown_multiplier *= status_cooldown_falloff_multiplier

		_play_jump_feedback(target_position, next_target.global_position)
		var attack_context: AttackComponent.AttackLineageContext = host.attack_component.create_derived_attack_context(
			initial_report,
			instance,
			true,
			target_position,
			true,
			current_damage,
			initial_report.get_attack_id(),
			true,
			current_status_cooldown_multiplier
		)
		if not is_instance_valid(attack_context):
			break
		host.attack_component.attack_with_context(next_target, attack_context, Vector2.ZERO, false, false)
		#update state for next loop iteration
		already_hit.append(next_target)
		target_position = next_target.global_position
		target_hostile = next_target.hostile
		await Clock.await_game_time(0.1)

func _find_next_jump_target(from_target_position: Vector2, from_target_hostile: bool, radius: float, excluded_targets: Array[Unit]) -> Unit: ##picks the nearest valid follow-up target that has not already been chained this cast
	#query combat manager for valid targets nearby
	var potential_targets: Array[Unit] = CombatManager.get_units_in_radius(
		radius,
		from_target_position,
		from_target_hostile,
		excluded_targets
	)

	#var closest_dist_sq: float = INF
	#var closest_target: Unit = null
#
	##simple nearest-neighbor search
	#for potential_target: Unit in potential_targets:
		#var dist_sq: float = from_target.global_position.distance_squared_to(potential_target.global_position)
		#if dist_sq < closest_dist_sq:
			#closest_dist_sq = dist_sq
			#closest_target = potential_target
	if potential_targets.is_empty():
		return null
	return potential_targets.pick_random()

func _get_attack_origin(host: Tower) -> Vector2: ##prefers the authored muzzle so hitscan feedback still starts from the actual firing point
	if not is_instance_valid(host) or not is_instance_valid(host.attack_component):
		return Vector2.ZERO

	if is_instance_valid(host.attack_component.muzzle):
		return host.attack_component.muzzle.global_position

	return host.global_position

func _play_jump_feedback(start_position: Vector2, end_position: Vector2) -> void: ##draws a short-lived translucent line so chained hits are easy to inspect during debugging
	if not show_jump_feedback:
		return

	if start_position.is_equal_approx(end_position):
		return

	for swirl_info: VFXInfo in jump_particle_swirls:
		if swirl_info == null:
			continue

		var swirl_line: SwirlLineVFX = VFXManager.play_swirl_line(
			start_position,
			end_position,
			swirl_info.swirl_color,
			swirl_info.swirl_width,
			swirl_info.lifetime,
			swirl_info.swirl_particles_per_tile,
			swirl_info.swirl_scale_min,
			swirl_info.swirl_scale_max,
			swirl_info.swirl_drift_speed_min,
			swirl_info.swirl_drift_speed_max,
			swirl_info.swirl_drift_angle_noise_deg,
			swirl_info.graphical_layer
		)
		if is_instance_valid(swirl_line) and is_instance_valid(swirl_info.swirl_particle_texture):
			swirl_line.set_texture(swirl_info.swirl_particle_texture)

	var line := Line2D.new()
	line.width = jump_feedback_width
	line.default_color = jump_feedback_color
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = Layers.ALLIED_PROJECTILES + 1
	line.z_as_relative = false
	line.add_point(start_position)
	line.add_point(end_position)
	if not VFXManager.add_exempt_node(line, Vector2.ZERO):
		return

	Clock.await_game_time(jump_feedback_duration).connect(func() -> void:
		if is_instance_valid(line):
			line.queue_free()
	, CONNECT_ONE_SHOT)
