# spawn_point_service.gd (Autoload Singleton)
extends Node

# we track the tower nodes themselves, not just their positions
var _breach_seeds: Array[Tower] = []
var _active_breaches: Array[Tower] = []

func _ready() -> void:
	# listen for new waves to update the state of all breaches
	Phases.wave_cycle_started.connect(_on_wave_cycle_started)

# called by Island when a breach tower is constructed
func register_breach(breach_tower: Tower) -> void:
	if breach_tower.type == Towers.Type.BREACH_SEED:
		_breach_seeds.append(breach_tower)
		# listen for its destruction to remove it from tracking
		breach_tower.died.connect(_on_breach_destroyed.bind(breach_tower), CONNECT_ONE_SHOT)
	
func _on_wave_cycle_started(wave_number: int) -> void:
	# --- 1. Mature Seeds into Breaches ---
	var seeds_to_mature: Array[Tower] = []
	for seed: Tower in _breach_seeds:
		# assume the seed has a 'waves_to_mature' parameter in its data
		var waves_left: int = seed.get_intrinsic_effect_attribute(Effects.Type.BREACH, &"waves_to_mature")
		if waves_left <= 1: # if this is the last wave of waiting
			seeds_to_mature.append(seed)
		else:
			# this is not a clean way to mutate effect state, but works for this example
			seed.effects_by_type[Effects.Type.BREACH][0].state[&"waves_to_mature"] -= 1

	for seed: Tower in seeds_to_mature:
		_breach_seeds.erase(seed)
		var cell: Vector2i = seed.tower_position
		var island: Island = seed.get_parent() as Island
		seed.queue_free() # remove the seed
		# create the active breach in its place
		var active_breach: Tower = island.construct_tower_at(cell, Towers.Type.BREACH, seed.facing)
		_active_breaches.append(active_breach)
		active_breach.died.connect(_on_breach_destroyed.bind(active_breach), CONNECT_ONE_SHOT)

	# --- 2. Close old Breaches ---
	var breaches_to_close: Array[Tower] = []
	for breach: Tower in _active_breaches:
		var waves_left: int = breach.get_intrinsic_effect_attribute(Effects.Type.BREACH, &"waves_to_live")
		if waves_left <= 1:
			breaches_to_close.append(breach)
		else:
			breach.effects_by_type[Effects.Type.BREACH][0].state[&"waves_to_live"] -= 1
			
	for breach: Tower in breaches_to_close:
		_active_breaches.erase(breach)
		breach.queue_free() # remove the breach tower

# the main public API for the Waves service
func get_spawn_points() -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for breach: Tower in _active_breaches:
		points.append(breach.tower_position)
	return points

func _on_breach_destroyed(breach_tower: Tower) -> void:
	_breach_seeds.erase(breach_tower)
	_active_breaches.erase(breach_tower)
