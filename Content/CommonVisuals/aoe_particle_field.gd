@tool
extends Node2D
class_name AoeParticleFieldVFX

class ParticleSpec extends RefCounted:
	var position: Vector2 = Vector2.ZERO
	var scale: float = 1.0
	var rotation: float = 0.0
	var angular_velocity: float = 0.0
	var alpha_multiplier: float = 1.0
	var velocity: Vector2 = Vector2.ZERO

const WORLD_SCALE: float = 0.06

var _texture: Texture2D
var _base_color: Color = Color.WHITE
var _lifetime: float = 0.35
var _age: float = 0.0
var _particles: Array[ParticleSpec] = []

func setup_from_info(info: VFXInfo, radius: float, cone_angle_deg: float = 360.0, aim_direction: Vector2 = Vector2.RIGHT) -> void: ##copies one resource's authored particle-field settings onto this runtime marker and rebuilds the particle layout
	_texture = info.aoe_particle_texture
	_base_color = info.aoe_particle_color
	_lifetime = info.aoe_particle_lifetime
	_particles = _generate_particles(info, radius, cone_angle_deg, aim_direction)
	z_as_relative = false
	z_index = info.graphical_layer
	_age = 0.0
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void: ##fades and retires the field in game time so paused combat also pauses the marker
	var delta: float = Clock.game_delta
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return

	for particle: ParticleSpec in _particles:
		particle.position += particle.velocity * delta

	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_texture) or _particles.is_empty():
		return

	var progress: float = clampf(_age / maxf(_lifetime, 0.001), 0.0, 1.0)
	var fade_alpha: float = 1.0 - progress ** 2
	var base_size: Vector2 = _texture.get_size() * WORLD_SCALE

	for particle: ParticleSpec in _particles:
		var color: Color = _base_color
		color.a *= particle.alpha_multiplier * fade_alpha
		var particle_scale: Vector2 = Vector2.ONE * particle.scale
		draw_set_transform(particle.position, particle.rotation + particle.angular_velocity * _age, Vector2.ONE)
		var draw_size: Vector2 = base_size * particle_scale * 2.0
		var draw_rect: Rect2 = Rect2(-draw_size * 0.5, draw_size)
		draw_texture_rect(_texture, draw_rect, false, color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _generate_particles(info: VFXInfo, radius: float, cone_angle_deg: float, aim_direction: Vector2) -> Array[ParticleSpec]: ##samples a dense static layout that fills the authored aoe shape rather than clustering only on the edge
	var output: Array[ParticleSpec] = []
	if not is_instance_valid(info.aoe_particle_texture):
		return output

	var particle_count: int = _get_particle_count(radius, cone_angle_deg, info.aoe_particles_per_cell)
	if particle_count <= 0:
		return output

	var direction: Vector2 = aim_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT

	var cone_angle_rad: float = TAU if _is_full_circle(cone_angle_deg) else deg_to_rad(cone_angle_deg)
	var center_angle: float = direction.angle()

	for i: int in range(particle_count):
		var particle := ParticleSpec.new()
		particle.position = _sample_shape_position(radius, cone_angle_rad, center_angle)
		particle.scale = randf_range(info.aoe_particle_scale_min, info.aoe_particle_scale_max)
		particle.rotation = randf() * TAU
		particle.angular_velocity = deg_to_rad(randf_range(info.aoe_particle_spin_speed_min, info.aoe_particle_spin_speed_max))
		particle.alpha_multiplier = randf_range(0.8, 1.0)
		particle.velocity = _sample_particle_velocity(info, particle.position, center_angle)
		output.append(particle)

	return output

func _get_particle_count(radius: float, cone_angle_deg: float, particles_per_cell: float) -> int: ##scales count by island cells so authored density stays readable across both small bursts and large cones
	if radius <= 0.0 or particles_per_cell <= 0.0:
		return 0

	var area_ratio: float = 1.0 if _is_full_circle(cone_angle_deg) else clampf(cone_angle_deg / 360.0, 0.0, 1.0)
	var shape_area: float = PI * radius * radius * area_ratio
	var cell_area: float = Island.CELL_SIZE * Island.CELL_SIZE
	var cells_covered: float = shape_area / maxf(cell_area, 1.0)
	return maxi(1, ceili(cells_covered * particles_per_cell))

func _sample_shape_position(radius: float, cone_angle_rad: float, center_angle: float) -> Vector2: ##uses sqrt radial sampling so particles look evenly filled across the aoe instead of clumping near the center
	var sample_angle: float = randf() * TAU
	if cone_angle_rad < TAU:
		sample_angle = randf_range(center_angle - cone_angle_rad * 0.5, center_angle + cone_angle_rad * 0.5)

	var sample_distance: float = sqrt(randf()) * radius
	return Vector2.from_angle(sample_angle) * sample_distance

func _sample_particle_velocity(info: VFXInfo, position: Vector2, fallback_angle: float) -> Vector2: ##biases particles away from the origin while adding angular noise so the field breathes instead of marching in lockstep
	var outward_direction: Vector2 = position.normalized()
	if outward_direction.is_zero_approx():
		outward_direction = Vector2.from_angle(fallback_angle)

	var noisy_angle: float = outward_direction.angle() + deg_to_rad(
		randf_range(-info.aoe_particle_drift_angle_noise_deg, info.aoe_particle_drift_angle_noise_deg)
	)
	var drift_speed: float = randf_range(info.aoe_particle_drift_speed_min, info.aoe_particle_drift_speed_max)
	return Vector2.from_angle(noisy_angle) * drift_speed

func _is_full_circle(cone_angle_deg: float) -> bool:
	return is_zero_approx(cone_angle_deg) or cone_angle_deg >= 360.0
