extends EffectPrototype
class_name ChainLightningEffect

const LINEAGE_LABEL: StringName = &"chain_lightning"

class ChainState extends RefCounted:
	var seen_attack_ids: Dictionary[int, bool] = {}
	var seen_feedback_attack_ids: Dictionary[int, bool] = {}
	var generation: int = 0

@export var max_jumps: int = 3 ##maximum number of secondary targets the arc may chain through after the primary hit
@export var jump_radius: float = 150.0 ##search radius for the next random living enemy, excluding this chain's previous targets
@export var jump_interval: float = 0.1 ##game-time spacing between scheduled hops; existing projectile travel remains separate
@export var damage_falloff_multiplier: float = 0.66 ##damage retained after each jump; values below one decay the chain
@export var status_cooldown_falloff_multiplier: float = 0.66 ##timed status duration retained after each jump; permanent statuses are unaffected
@export var show_jump_feedback: bool = true ##draws the authored lightning lines and swirl layers for the initial strike and hops
@export var jump_feedback_color: Color = Color(1.0, 0.9, 0.2, 0.45) ##lightning line tint shared by the root strike and chained jumps
@export var jump_feedback_width: float = 3.0 ##lightning overlay line width
@export var jump_feedback_duration: float = 0.18 ##seconds each lightning line persists before cleanup
@export var jump_particle_swirls: Array[VFXInfo] = [] ##authored swirl layers drawn underneath each visible lightning segment

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_DEALT, GameEvent.EventType.WAVE_STARTED, GameEvent.EventType.WAVE_ENDED]

func create_instance() -> EffectInstance: ##owns deduplication and cancellation per effect instance, not on the shared resource
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = ChainState.new()
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(instance: EffectInstance) -> void: ##invalidates pending hops on ruin, removal, or reattachment
	var state: ChainState = instance.state as ChainState
	state.generation += 1
	state.seen_attack_ids.clear()
	state.seen_feedback_attack_ids.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##draws each real offensive hit group once and separately admits damaging groups for propagation
	var state: ChainState = instance.state as ChainState
	if event.event_type in [GameEvent.EventType.WAVE_STARTED, GameEvent.EventType.WAVE_ENDED]:
		state.generation += 1
		state.seen_attack_ids.clear()
		state.seen_feedback_attack_ids.clear()
		return
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	var hit_report: HitReportData = event.data as HitReportData
	if hit_report == null or not hit_report.real or hit_report.attack_id <= 0:
		return
	if not is_instance_valid(hit_report.incoming_hit):
		return
	if hit_report.has_lineage_producer(instance) or hit_report.has_lineage_producer_label(LINEAGE_LABEL):
		return

	var host_tower: Tower = instance.host as Tower
	if not is_instance_valid(host_tower) or not is_instance_valid(host_tower.attack_component):
		return
	if host_tower.abstractive or host_tower.incorporeal or host_tower.disabled:
		return
	if host_tower.is_queued_for_deletion() or not host_tower.is_inside_tree():
		return
	if hit_report.source != host_tower or not is_instance_valid(hit_report.target):
		return
	if hit_report.target.hostile == host_tower.hostile:
		return
	if not Run.is_run_ready() or Run.phases.current_phase != Run.phases.GamePhase.COMBAT_WAVE:
		return
	#the root strike is visible even when wheel removes direct damage and no chain is admitted.
	if HitReportData.consume_attack_id(hit_report, state.seen_feedback_attack_ids):
		_play_jump_feedback(_get_attack_origin(host_tower), hit_report.target.global_position)
	if hit_report.incoming_damage <= 0.0:
		return
	if not HitReportData.consume_attack_id(hit_report, state.seen_attack_ids):
		return

	_execute_chain_lightning(instance, host_tower, hit_report)

func _execute_chain_lightning(instance: EffectInstance, host: Tower, initial_report: HitReportData) -> void: ##continues a frozen payload without rerunning outgoing attack hooks or importing the first victim's defenses
	var state: ChainState = instance.state as ChainState
	var generation: int = state.generation
	var template_hit := initial_report.incoming_hit.duplicate() as HitData
	template_hit.damage = initial_report.incoming_damage
	template_hit.status_effects = initial_report.incoming_status_effects.duplicate()
	template_hit.radius = 0.0
	template_hit.primary = false
	template_hit.vfx_on_spawn = null
	template_hit.vfx_on_impact = null
	template_hit.fire_sound = &""
	var target_hostile: bool = initial_report.target.hostile
	var target_position: Vector2 = initial_report.target.global_position
	var already_hit: Array[Unit] = [initial_report.target]

	var current_damage: float = template_hit.damage
	var current_status_cooldown_multiplier: float = 1.0

	for jump_index: int in range(maxi(max_jumps, 0)):
		if not is_instance_valid(instance) or not instance.enabled or state.generation != generation:
			return
		if not is_instance_valid(host) or host.disabled or host.is_queued_for_deletion() or not host.is_inside_tree():
			return
		if host.hostile == target_hostile:
			return
		if not Run.is_run_ready() or not is_instance_valid(host.attack_component):
			return
		var next_target: Unit = _find_next_jump_target(target_position, target_hostile, jump_radius, already_hit)

		if not is_instance_valid(next_target):
			break

		current_damage *= maxf(damage_falloff_multiplier, 0.0)
		current_status_cooldown_multiplier *= maxf(status_cooldown_falloff_multiplier, 0.0)
		if current_damage <= 0.0:
			break

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
		var jump_hit := template_hit.duplicate() as HitData
		if not host.attack_component.apply_attack_context(jump_hit, attack_context):
			break
		jump_hit.lineage.push_producer_label(LINEAGE_LABEL)
		jump_hit.target = next_target
		jump_hit.target_affiliation = target_hostile
		var delivery_data: DeliveryData = host.attack_component.generate_delivery_data()
		delivery_data.target = next_target
		delivery_data.use_source_position_override = true
		delivery_data.source_position = target_position
		delivery_data.intercept_position = next_target.global_position
		_play_jump_feedback(target_position, delivery_data.intercept_position)
		already_hit.append(next_target)
		target_position = delivery_data.intercept_position
		CombatManager.resolve_hit(jump_hit, delivery_data)
		if jump_index + 1 < max_jumps:
			await Clock.await_game_time(maxf(jump_interval, 0.0))

func _find_next_jump_target(from_target_position: Vector2, from_target_hostile: bool, radius: float, excluded_targets: Array[Unit]) -> Unit: ##retains random targeting while rejecting dead, disabled, and non-gameplay candidates
	if radius <= 0.0:
		return null
	var potential_targets: Array[Unit] = CombatManager.get_units_in_radius(
		radius,
		from_target_position,
		from_target_hostile,
		excluded_targets
	)

	for index: int in range(potential_targets.size() - 1, -1, -1):
		var candidate: Unit = potential_targets[index]
		if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			potential_targets.remove_at(index)
			continue
		if candidate.hostile != from_target_hostile or candidate.disabled or candidate.incorporeal or candidate.abstractive:
			potential_targets.remove_at(index)
			continue
		if not is_instance_valid(candidate.health_component) or candidate.health_component.health <= 0.0:
			potential_targets.remove_at(index)
	if potential_targets.is_empty():
		return null
	return potential_targets.pick_random()

func _get_attack_origin(host: Tower) -> Vector2: ##anchors the initial lightning segment to the authored muzzle when available
	if not is_instance_valid(host) or not is_instance_valid(host.attack_component):
		return Vector2.ZERO

	if is_instance_valid(host.attack_component.muzzle):
		return host.attack_component.muzzle.global_position

	return host.global_position

func _play_jump_feedback(start_position: Vector2, end_position: Vector2) -> void: ##draws the authored lightning and swirl layers independently of projectile presentation
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
