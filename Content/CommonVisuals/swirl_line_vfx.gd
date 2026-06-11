@tool
extends Node2D
class_name SwirlLineVFX

class ParticleSpec extends RefCounted:
	var position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO
	var scale: float = 1.0
	var rotation: float = 0.0
	var angular_velocity: float = 0.0
	var alpha_multiplier: float = 1.0
	var age: float = 0.0
	var lifetime: float = 0.35

const WORLD_SCALE: float = 0.06
const DEFAULT_TEXTURE: Texture2D = preload("res://Assets/particle_whirl.png")

var _start_position: Vector2 = Vector2.ZERO
var _end_position: Vector2 = Vector2.ZERO
var _texture: Texture2D = DEFAULT_TEXTURE
var _color: Color = Color.WHITE
var _lifetime: float = 0.35
var _age: float = 0.0
var _particles: Array[ParticleSpec] = []
var _persistent: bool = false
var _width: float = 10.0
var _particles_per_tile: float = 2.0
var _scale_min: float = 0.45
var _scale_max: float = 0.85
var _drift_speed_min: float = 4.0
var _drift_speed_max: float = 12.0
var _drift_angle_noise_deg: float = 35.0
var _spawn_accumulator: float = 0.0

func configure(
	start_position: Vector2,
	end_position: Vector2,
	color: Color,
	width: float = 10.0,
	lifetime: float = 0.35,
	particles_per_tile: float = 2.0,
	scale_min: float = 0.45,
	scale_max: float = 0.85,
	drift_speed_min: float = 4.0,
	drift_speed_max: float = 12.0,
	drift_angle_noise_deg: float = 35.0
) -> void: ##builds a short-lived swirl line for one-shot pulses and telegraphs
	_persistent = false
	_apply_common_config(
		start_position,
		end_position,
		color,
		width,
		lifetime,
		particles_per_tile,
		scale_min,
		scale_max,
		drift_speed_min,
		drift_speed_max,
		drift_angle_noise_deg
	)
	_particles = _generate_particles()
	set_process(true)
	queue_redraw()

func configure_persistent(
	start_position: Vector2,
	end_position: Vector2,
	color: Color,
	width: float = 10.0,
	particle_lifetime: float = 0.35,
	particles_per_tile: float = 2.0,
	scale_min: float = 0.45,
	scale_max: float = 0.85,
	drift_speed_min: float = 4.0,
	drift_speed_max: float = 12.0,
	drift_angle_noise_deg: float = 35.0
) -> void: ##starts a self-refreshing diffuse beam that stays alive until the owner releases it
	_persistent = true
	_apply_common_config(
		start_position,
		end_position,
		color,
		width,
		particle_lifetime,
		particles_per_tile,
		scale_min,
		scale_max,
		drift_speed_min,
		drift_speed_max,
		drift_angle_noise_deg
	)
	_particles.clear()
	_spawn_accumulator = 0.0
	_emit_persistent_particles(1.0)
	set_process(true)
	queue_redraw()

func set_segment(start_position: Vector2, end_position: Vector2) -> void: ##moves a persistent beam to new endpoints without rebuilding the effect node
	_start_position = start_position
	_end_position = end_position
	if _persistent:
		queue_redraw()

func stop() -> void: ##lets owners clear a persistent beam deliberately before the node leaves the tree
	queue_free()

func set_texture(texture: Texture2D) -> void: ##lets authored resources override the default swirl sprite without forking the effect node
	_texture = texture if is_instance_valid(texture) else DEFAULT_TEXTURE

func _process(_delta: float) -> void: ##advances existing particles and refreshes live beams at game-time speed
	var delta: float = Clock.game_delta
	_age += delta
	if not _persistent and _age >= _lifetime:
		queue_free()
		return

	for particle: ParticleSpec in _particles:
		particle.age += delta
		particle.position += particle.velocity * delta

	for i: int in range(_particles.size() - 1, -1, -1):
		if _particles[i].age >= _particles[i].lifetime:
			_particles.remove_at(i)

	if _persistent:
		_emit_persistent_particles(delta)

	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_texture) or _particles.is_empty():
		return

	var base_size: Vector2 = _texture.get_size() * WORLD_SCALE

	for particle: ParticleSpec in _particles:
		var fade_alpha: float = 1.0 - clampf(particle.age / maxf(particle.lifetime, 0.001), 0.0, 1.0)
		var draw_color: Color = _color
		draw_color.a *= particle.alpha_multiplier * fade_alpha
		draw_set_transform(particle.position, particle.rotation + particle.angular_velocity * _age, Vector2.ONE)
		var draw_size: Vector2 = base_size * particle.scale
		draw_texture_rect(_texture, Rect2(-draw_size * 0.5, draw_size), false, draw_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _apply_common_config(
	start_position: Vector2,
	end_position: Vector2,
	color: Color,
	width: float,
	lifetime: float,
	particles_per_tile: float,
	scale_min: float,
	scale_max: float,
	drift_speed_min: float,
	drift_speed_max: float,
	drift_angle_noise_deg: float
) -> void: ##stores the authored beam parameters once so pulse and persistent variants share the same shaping code
	_start_position = start_position
	_end_position = end_position
	_texture = DEFAULT_TEXTURE
	_color = color
	_width = width
	_lifetime = lifetime
	_particles_per_tile = particles_per_tile
	_scale_min = scale_min
	_scale_max = scale_max
	_drift_speed_min = drift_speed_min
	_drift_speed_max = drift_speed_max
	_drift_angle_noise_deg = drift_angle_noise_deg
	_age = 0.0

func _generate_particles() -> Array[ParticleSpec]: ##samples an initial line of particles for a one-shot pulse
	var output: Array[ParticleSpec] = []
	var segment: Vector2 = _end_position - _start_position
	var length: float = segment.length()
	if is_zero_approx(length):
		return output

	var direction: Vector2 = segment / length
	var normal: Vector2 = direction.orthogonal()
	var particle_count: int = maxi(1, ceili((length / maxf(Island.CELL_SIZE, 1.0)) * _particles_per_tile))

	for i: int in range(particle_count):
		output.append(_create_particle(direction, normal))

	return output

func _emit_persistent_particles(delta: float) -> void: ##feeds a live beam with a steady particle stream so it reads as continuous instead of strobing
	var segment: Vector2 = _end_position - _start_position
	var length: float = segment.length()
	if is_zero_approx(length):
		return

	var spawn_rate: float = maxf((length / maxf(Island.CELL_SIZE, 1.0)) * _particles_per_tile * 8.0, 1.0)
	_spawn_accumulator += spawn_rate * delta

	var direction: Vector2 = segment / length
	var normal: Vector2 = direction.orthogonal()
	while _spawn_accumulator >= 1.0:
		_spawn_accumulator -= 1.0
		_particles.append(_create_particle(direction, normal))

func _create_particle(direction: Vector2, normal: Vector2) -> ParticleSpec: ##creates one local-space swirl particle using the current beam settings
	var particle := ParticleSpec.new()
	var t: float = randf()
	var line_position: Vector2 = _start_position.lerp(_end_position, t)
	var lateral_offset: float = randf_range(-_width * 0.5, _width * 0.5)
	particle.position = line_position + normal * lateral_offset - global_position
	particle.scale = randf_range(_scale_min, _scale_max)
	particle.rotation = randf() * TAU
	particle.angular_velocity = deg_to_rad(randf_range(-55.0, 55.0))
	particle.alpha_multiplier = randf_range(0.75, 1.0)
	particle.velocity = _sample_velocity(direction, normal, _drift_speed_min, _drift_speed_max, _drift_angle_noise_deg)
	particle.lifetime = _lifetime if _lifetime > 0.0 else 0.35
	return particle

func _sample_velocity(direction: Vector2, normal: Vector2, drift_speed_min: float, drift_speed_max: float, drift_angle_noise_deg: float) -> Vector2: ##pushes particles roughly along the line with noisy lateral wobble so the effect stays diffuse
	var base_direction: Vector2 = direction if randf() < 0.5 else -direction
	base_direction = (base_direction + normal * randf_range(-0.35, 0.35)).normalized()
	var noisy_angle: float = base_direction.angle() + deg_to_rad(randf_range(-drift_angle_noise_deg, drift_angle_noise_deg))
	var drift_speed: float = randf_range(drift_speed_min, drift_speed_max)
	return Vector2.from_angle(noisy_angle) * drift_speed
