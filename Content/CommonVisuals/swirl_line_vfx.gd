extends GPUParticles2D
class_name SwirlLineVFX

const WORLD_SCALE: float = 0.06
const DEFAULT_TEXTURE: Texture2D = preload("res://Assets/particle_whirl.png")
const PARTICLE_SHADER: Shader = preload("res://Content/CommonVisuals/swirl_line_particles.gdshader")
const STREAM_RATE_PER_TILE: float = 8.0

var flow_strength: float = 1.0: ##scales opacity and particle drift together for owner-driven transitions
	set(value):
		flow_strength = clampf(value, 0.0, 1.0)
		self_modulate.a = flow_strength
		if _particle_material != null:
			_particle_material.set_shader_parameter(&"flow_strength", flow_strength)

var _particle_material: ShaderMaterial
var _start_position: Vector2
var _end_position: Vector2
var _particles_per_tile: float
var _drift_margin: float
var _max_sprite_scale: float

func configure(
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
) -> void: ##emits one burst across the line and releases it after one game-time lifetime
	one_shot = true
	explosiveness = 1.0
	_configure_emitter(start_position, end_position, color, width, particle_lifetime, particles_per_tile,
		scale_min, scale_max, drift_speed_min, drift_speed_max, drift_angle_noise_deg, false)
	Clock.await_game_time(lifetime).connect(queue_free, CONNECT_ONE_SHOT)

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
	drift_angle_noise_deg: float = 35.0,
	forward_only: bool = false
) -> void: ##emits continuously until the owner stops the stream
	_configure_emitter(start_position, end_position, color, width, particle_lifetime, particles_per_tile,
		scale_min, scale_max, drift_speed_min, drift_speed_max, drift_angle_noise_deg, forward_only)

func set_segment(start_position: Vector2, end_position: Vector2) -> void: ##updates the spawn line and resizes the emitter only when its particle count changes
	if start_position == _start_position and end_position == _end_position:
		return
	_start_position = start_position
	_end_position = end_position
	var segment: Vector2 = end_position - start_position
	_particle_material.set_shader_parameter(&"line_start", start_position)
	_particle_material.set_shader_parameter(&"line_delta", segment)
	var particles_per_cycle: float = segment.length() / Island.CELL_SIZE * _particles_per_tile
	if not one_shot:
		particles_per_cycle *= STREAM_RATE_PER_TILE * lifetime
	var next_amount: int = maxi(1, ceili(particles_per_cycle))
	if amount != next_amount:
		amount = next_amount
	_update_visibility_bounds()

func stop() -> void: ##releases a persistent stream when its owner detaches
	queue_free()

func set_swirl_texture(particle_texture: Texture2D) -> void: ##applies an authored sprite and includes its size in the culling bounds
	texture = particle_texture if is_instance_valid(particle_texture) else DEFAULT_TEXTURE
	_update_visibility_bounds()

func _configure_emitter(
	start_position: Vector2,
	end_position: Vector2,
	color: Color,
	width: float,
	particle_lifetime: float,
	particles_per_tile: float,
	scale_min: float,
	scale_max: float,
	drift_speed_min: float,
	drift_speed_max: float,
	drift_angle_noise_deg: float,
	forward_only: bool
) -> void: ##configures one emitter on the existing world-following canvas
	lifetime = particle_lifetime if particle_lifetime > 0.0 else 0.35
	local_coords = true
	fixed_fps = 0
	draw_order = DRAW_ORDER_INDEX
	texture = DEFAULT_TEXTURE
	_particles_per_tile = particles_per_tile
	_drift_margin = absf(width) * 0.5 + maxf(absf(drift_speed_min), absf(drift_speed_max)) * lifetime
	_max_sprite_scale = maxf(absf(scale_min), absf(scale_max)) * WORLD_SCALE

	_particle_material = ShaderMaterial.new()
	_particle_material.shader = PARTICLE_SHADER
	_particle_material.set_shader_parameter(&"swirl_color", color)
	_particle_material.set_shader_parameter(&"half_width", width * 0.5)
	_particle_material.set_shader_parameter(&"sprite_scale", Vector2(scale_min, scale_max) * WORLD_SCALE)
	_particle_material.set_shader_parameter(&"drift_speed", Vector2(drift_speed_min, drift_speed_max))
	_particle_material.set_shader_parameter(&"angle_noise", deg_to_rad(drift_angle_noise_deg))
	_particle_material.set_shader_parameter(&"forward_only", forward_only)
	_particle_material.set_shader_parameter(&"flow_strength", flow_strength)
	process_material = _particle_material
	set_segment(start_position, end_position)

	speed_scale = Clock.speed_multiplier
	Clock.speed_changed.connect(_on_speed_changed)
	Run.run_ending.connect(queue_free, CONNECT_ONE_SHOT)
	restart()

func _update_visibility_bounds() -> void: ##covers the spawn line, particle travel and the rotated sprite corners
	var padding: float = _drift_margin + texture.get_size().length() * _max_sprite_scale * 0.5
	visibility_rect = Rect2(_start_position, _end_position - _start_position).abs().grow(padding)

func _on_speed_changed(multiplier: float) -> void: ##matches particle motion and lifetime to the game's speed setting
	speed_scale = multiplier
