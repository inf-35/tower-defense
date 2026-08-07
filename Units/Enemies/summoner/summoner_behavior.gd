extends Behavior
class_name SummonerBehavior

@export var spawn_unit_type: Units.Type = Units.Type.BASIC
@export var spawn_count: int = 3
@export var spawn_radius: float = 12.0
@export var max_spawn_attempts: int = 10
@export var summon_vfx: VFXInfo ##aoe field played when the summoner opens a portal

func start() -> void:
	super.start()

func update(_delta: float) -> void:
	if not _is_summon_ready():
		return

	_summon_children()
	attack_component.refresh_cooldown()

func _is_summon_ready() -> bool:
	if not is_instance_valid(unit):
		return false
	if not is_instance_valid(attack_component):
		return false
	return attack_component.current_cooldown <= 0.0

func _summon_children() -> void:
	if not is_instance_valid(Run.waves):
		return

	_play_animation(&"cast")
	_spawn_summon_vfx()
	ParticleManager.play_particles(ID.Particles.ENEMY_HIT_SPARKS, unit.global_position)

	for i: int in range(spawn_count):
		var spawn_position: Vector2 = _get_valid_spawn_position_near(unit.global_position, spawn_radius, max_spawn_attempts)
		Run.waves.spawn_enemy(spawn_unit_type, spawn_position)

func _spawn_summon_vfx() -> void:
	if not is_instance_valid(unit):
		return
	if not is_instance_valid(summon_vfx):
		return

	VFXManager.play_aoe_field(summon_vfx, unit.global_position, spawn_radius)

func get_display_data() -> Dictionary:
	return {
		&"spawn_count": spawn_count,
	}
