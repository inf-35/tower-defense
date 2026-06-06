#spawn_point_service.gd (autoload singleton)
extends Node

signal spawn_points_changed()

var _breach_seeds: Array[Tower] = []
var _active_breaches: Array[Tower] = []
var _tracked_breaches: Dictionary = {}

func start() -> void:
	_breach_seeds.clear()
	_active_breaches.clear()
	_tracked_breaches.clear()

func register_breach(breach_tower: Tower, seed: bool = true) -> void:
	assert(breach_tower.type == Towers.Type.BREACH, "SpawnPointService.register_breach expects a breach tower.")

	var previous_active_signature: int = _get_active_signature()
	_track_breach(breach_tower)

	if seed:
		if not _breach_seeds.has(breach_tower):
			_breach_seeds.append(breach_tower)
		_active_breaches.erase(breach_tower)
	else:
		_breach_seeds.erase(breach_tower)
		if not _active_breaches.has(breach_tower):
			_active_breaches.append(breach_tower)

	_emit_if_active_changed(previous_active_signature)

func get_spawn_points() -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for breach: Tower in _active_breaches:
		points.append(breach.tower_position)
	return points

func _track_breach(breach_tower: Tower) -> void:
	if _tracked_breaches.has(breach_tower):
		return

	breach_tower.died.connect(func(_hit_report_data): _on_breach_destroyed(breach_tower), CONNECT_ONE_SHOT)
	breach_tower.tree_exiting.connect(func(): _on_breach_destroyed(breach_tower), CONNECT_ONE_SHOT)
	_tracked_breaches[breach_tower] = true

func _on_breach_destroyed(breach_tower: Tower) -> void:
	var previous_active_signature: int = _get_active_signature()
	_breach_seeds.erase(breach_tower)
	_active_breaches.erase(breach_tower)
	_tracked_breaches.erase(breach_tower)
	_emit_if_active_changed(previous_active_signature)

func _emit_if_active_changed(previous_active_signature: int) -> void:
	if previous_active_signature != _get_active_signature():
		spawn_points_changed.emit()

func _get_active_signature() -> int:
	var hash_sum: int = 0
	var hash_xor: int = 0
	for breach: Tower in _active_breaches:
		var breach_hash: int = hash(breach.tower_position)
		hash_sum += breach_hash
		hash_xor ^= breach_hash
	return hash([_active_breaches.size(), hash_sum, hash_xor])

func _ready() -> void:
	set_process(false)
