extends Area2D
class_name PrismLaser

@export var collision_shape: CollisionShape2D
@export var beam_color: Color = Color(1.0, 0.864, 0.32, 0.459) ##tint for the soft particle beam between linked prisms
@export var beam_width: float = 9.0 ##world-space thickness of the particle cloud around the prism link
@export var particle_lifetime: float = 0.8 ##seconds each beam particle stays visible before fading out
@export var particles_per_tile: float = 2.5 ##particle density along the beam measured per island tile
@export var particle_scale_min: float = 0.5 ##smallest particle scale used by the prism cloud beam
@export var particle_scale_max: float = 1.0 ##largest particle scale used by the prism cloud beam
@export var drift_speed_min: float = 2.0 ##minimum particle drift speed after spawn
@export var drift_speed_max: float = 20.0 ##maximum particle drift speed after spawn
@export var drift_angle_noise_deg: float = 5.0 ##random angle wobble so the beam reads as a cloud, not a line

var prism_a: Tower
var prism_b: Tower

var _targets_in_area: Array[Unit] = []
var _visual_beam: SwirlLineVFX

func _ready() -> void:
	if not _has_valid_prisms():
		queue_free()
		return

	self.collision_layer = 0
	self.collision_mask = Hitbox.get_mask(not prism_a.hostile)
	self.monitoring = true
	self.monitorable = false
	self.z_index = Layers.ALLIED_PROJECTILES

	self.area_entered.connect(_on_area_entered)
	self.area_exited.connect(_on_area_exited)

func _process(_delta: float) -> void:
	if not _has_valid_prisms():
		queue_free()
		return

	_update_visual_beam()

func _on_area_entered(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		if not _targets_in_area.has(area.unit):
			_targets_in_area.append(area.unit)

func _on_area_exited(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		_targets_in_area.erase(area.unit)

func get_targets() -> Array[Unit]: ##returns the current valid units intersecting this beam without applying damage itself
	if not _has_valid_prisms():
		queue_free()
		return []

	var valid_targets: Array[Unit] = []
	for i: int in range(_targets_in_area.size() - 1, -1, -1):
		var target: Unit = _targets_in_area[i]
		if not is_instance_valid(target):
			_targets_in_area.remove_at(i)
			continue
		valid_targets.append(target)
	return valid_targets

func _update_visual_beam() -> void: ##keeps the particle cloud aligned to the two linked prism centers
	var start_position: Vector2 = Island.cell_to_position(prism_a.tower_position)
	var end_position: Vector2 = Island.cell_to_position(prism_b.tower_position)
	if not is_instance_valid(_visual_beam):
		_visual_beam = VFXManager.create_swirl_beam(
			start_position,
			end_position,
			beam_color,
			beam_width,
			particle_lifetime,
			particles_per_tile,
			particle_scale_min,
			particle_scale_max,
			drift_speed_min,
			drift_speed_max,
			drift_angle_noise_deg,
			Layers.ALLIED_PROJECTILES
		)
		return

	_visual_beam.set_segment(start_position, end_position)

func _has_valid_prisms() -> bool:
	return _is_valid_prism(prism_a) and _is_valid_prism(prism_b)

func _is_valid_prism(prism: Tower) -> bool:
	return is_instance_valid(prism) and not prism.is_queued_for_deletion() and not prism.disabled

func _exit_tree() -> void:
	if is_instance_valid(_visual_beam):
		_visual_beam.stop()
