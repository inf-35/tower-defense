# spawn_point_service.gd (Autoload Singleton)
extends Node

# we track the tower nodes themselves, not just their positions
var _breach_seeds: Array[Tower] = []
var _active_breaches: Array[Tower] = []

# called by Island when a breach tower is constructed
func register_breach(breach_tower: Tower, seed: bool = true) -> void:
	if breach_tower.type == Towers.Type.BREACH:
		if seed:
			_breach_seeds.append(breach_tower)
		else:
			_active_breaches.append(breach_tower)
		# listen for its destruction to remove it from tracking
		if not _breach_seeds.has(breach_tower):
			breach_tower.died.connect(_on_breach_destroyed.bind(breach_tower), CONNECT_ONE_SHOT)
		else:
			_breach_seeds.erase(breach_tower)

# the main public API for the Waves service
func get_spawn_points() -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for breach: Tower in _active_breaches:
		points.append(breach.tower_position)
	return points

func _on_breach_destroyed(breach_tower: Tower) -> void:
	_breach_seeds.erase(breach_tower)
	_active_breaches.erase(breach_tower)

func _ready():
	set_process(false)
