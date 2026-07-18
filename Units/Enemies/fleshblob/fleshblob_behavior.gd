extends DefaultBehavior
class_name FleshblobBehavior

@export var spawn_unit_type: Units.Type = Units.Type.FLESHLET
@export var spawn_count: int = 3
@export var spread_radius: float = 10.0

func start() -> void:
	super.start()
	if not unit.died.is_connected(_on_unit_died):
		unit.died.connect(_on_unit_died, CONNECT_ONE_SHOT)

func _on_unit_died(_hit_report_data: HitReportData) -> void:
	_spawn_children(unit.global_position)

func _spawn_children(origin_position: Vector2) -> void:
	if not is_instance_valid(Run.waves):
		return

	for i: int in range(spawn_count):
		var spawn_position: Vector2 = _get_valid_spawn_position_near(origin_position, spread_radius)
		Run.waves.spawn_enemy(spawn_unit_type, spawn_position)

func get_display_data() -> Dictionary:
	return {
		&"split_count": spawn_count,
	}
