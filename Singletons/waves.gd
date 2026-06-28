#waves.gd
extends Node #"Service" type singleton, mainly called by Phases
class_name Waves

signal wave_started(wave_number_int: int)
signal wave_ended(wave_number_int: int)

#--- state ---
var current_combat_wave_number: int = 0
var _total_enemies_planned: int = 0:
	set(nia):
		_total_enemies_planned = nia
var _enemies_spawned: int = 0
var _enemies_killed: int = 0
var _enemies_planned: Array[Array] = []
var _wave_enemy_preview_cache: Dictionary[int, Array] = {}
var _breach_enemy_assignments: Dictionary[int, Array] = {}
var _frozen_raider_waypoints: Dictionary[int, Array] = {}

#--- configuration ---
const CONCURRENT_ENEMY_SPAWNS: int = 10
const WAVES_PER_EXPANSION_CHOICE: int = 3
const DELAY_AFTER_BUILDING_PHASE_ENDS: float = 0.5

#--- reconciliation system ---
const ENEMY_GROUP: StringName = &"active_enemies"
var _reconciliation_timer: Timer


func _ready() -> void:
	if is_instance_valid(Run.phases) and not Run.phases.wave_cycle_started.is_connected(_on_wave_cycle_started):
		Run.phases.wave_cycle_started.connect(_on_wave_cycle_started)
	if not SpawnPointService.spawn_points_changed.is_connected(_refresh_breach_enemy_assignments):
		SpawnPointService.spawn_points_changed.connect(_refresh_breach_enemy_assignments)

	wave_started.connect(func(wave: int):
		var wave_data := WaveData.new()
		wave_data.wave = wave

		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.WAVE_STARTED
		evt.data = wave_data

		Run.player.on_event.emit(null, evt)
	)

	wave_ended.connect(func(wave: int):
		var wave_data := WaveData.new()
		wave_data.wave = wave

		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.WAVE_ENDED
		evt.data = wave_data

		Run.player.on_event.emit(null, evt)
	)

	_reconciliation_timer = Timer.new()
	add_child(_reconciliation_timer)
	_reconciliation_timer.one_shot = false
	_reconciliation_timer.autostart = true
	_reconciliation_timer.start(3.0)
	_reconciliation_timer.timeout.connect(_reconcile_enemy_count)

func get_planned_enemies_for_wave(wave: int) -> Array[Array]: ##returns the stable planned enemy roster for the active wave cycle and falls back to generated data otherwise
	if wave <= 0:
		return []

	if _wave_enemy_preview_cache.has(wave):
		var cached_wave_stacks: Array[Array] = _wave_enemy_preview_cache[wave]
		return cached_wave_stacks.duplicate(true)

	if is_instance_valid(Run.phases) and wave == Run.phases.current_wave_number:
		_cache_wave_enemy_plan(wave)
		var current_wave_stacks: Array[Array] = _wave_enemy_preview_cache.get(wave, [])
		return current_wave_stacks.duplicate(true)

	return WaveEnemies.get_enemies_for_wave(wave)

func get_breach_wave_preview(breach: Tower) -> String: ##returns one compact comma-delimited preview of the next wave roster assigned to this active breach
	if not is_instance_valid(breach):
		return ""

	var assigned_stacks: Array[Array] = _breach_enemy_assignments.get(breach.unit_id, [])
	if assigned_stacks.is_empty():
		return ""

	assigned_stacks.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) < int(b[0])
	)

	var parts: Array[String] = []
	for enemy_stack: Array in assigned_stacks:
		var unit_type: Units.Type = enemy_stack[0]
		var unit_count: int = int(enemy_stack[1])
		if unit_count <= 0:
			continue

		parts.append("{U_%s} x%d" % [Units.Type.keys()[unit_type], unit_count])

	return "\n" + ", ".join(parts)

#main function called by phases.gd to start a combat wave
func start_combat_wave(wave_num_to_spawn: int) -> void:
	if current_combat_wave_number > 0:
		push_warning("Waves: start_combat_wave called while another wave is active. Ignoring.")
		return
	if wave_num_to_spawn <= 0:
		push_error("Waves: start_combat_wave called with invalid wave number.")
		return

	current_combat_wave_number = wave_num_to_spawn

	#reset all counters for the new wave
	_cache_wave_enemy_plan(current_combat_wave_number)
	_enemies_planned = get_planned_enemies_for_wave(current_combat_wave_number)
	_total_enemies_planned = WaveEnemies.get_enemy_count(_enemies_planned)
	_enemies_spawned = 0
	_enemies_killed = 0
	_refresh_breach_enemy_assignments()
	_freeze_raider_waypoints()


	print("Waves: Starting combat for wave %d with %d planned enemies." % [current_combat_wave_number, _total_enemies_planned])
	wave_started.emit(current_combat_wave_number)

	if _total_enemies_planned > 0:
		_spawn_enemies_for_current_wave()
	else:
		#if no enemies are planned, end the wave immediately
		_end_combat_wave()

func _spawn_enemies_for_current_wave() -> void:
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	if spawn_points.is_empty():
		push_warning("Waves: No active breaches found. Cannot spawn enemies.")
		_end_combat_wave() #end the wave if we can't spawn anything
		return

	var enemies_to_spawn: Array = _enemies_planned
	var enemy_stagger: float = 5.0 / _total_enemies_planned
	var spawn_point_index: int = 0


	for enemy_stack: Array in enemies_to_spawn:
		var unit_type: Units.Type = enemy_stack[0]
		var unit_stack_count: int = enemy_stack[1]

		for i: int in unit_stack_count:
			#if a new wave has started while we were spawning, abort
			if current_combat_wave_number == 0:
				return

			var spawn_cell: Vector2i = spawn_points[spawn_point_index]
			spawn_point_index = (spawn_point_index + 1) % spawn_points.size()
			spawn_enemy(unit_type, Island.cell_to_position(spawn_cell))

			await Clock.await_game_time(enemy_stagger * 0.6)

		await Clock.await_game_time(enemy_stagger * 0.8)

func spawn_enemy(unit_type: Units.Type, position: Vector2) -> Unit:
	var unit: Unit = Units.create_unit(unit_type)
	unit.add_to_group(ENEMY_GROUP)
	unit.died.connect(func(_hit_report_data): _on_enemy_died(unit), CONNECT_ONE_SHOT)
	Run.references.island.add_child.call_deferred(unit)
	unit.movement_component.set_deferred(&"position", position)

	#increment the spawned counter only after the unit is created
	_enemies_spawned += 1
	return unit

func _on_wave_cycle_started(wave_number: int) -> void: ##seeds a stable roster for the newly prepared wave and rebuilds any per-breach previews against it
	_cache_wave_enemy_plan(wave_number)
	_refresh_breach_enemy_assignments()

func _cache_wave_enemy_plan(wave: int) -> void:
	if wave <= 0:
		return
	if _wave_enemy_preview_cache.has(wave):
		return

	_wave_enemy_preview_cache[wave] = WaveEnemies.get_enemies_for_wave(wave).duplicate(true)

func get_frozen_raider_waypoints(spawn_cell: Vector2i, ignore_walls: bool) -> Array[Vector2i]: ##returns the combat-wave-frozen ordered raid target list for one spawn/mode pair
	var frozen_waypoints: Array[Vector2i] = []
	frozen_waypoints.assign(_frozen_raider_waypoints.get(_make_raider_waypoint_key(spawn_cell, ignore_walls), []))
	return frozen_waypoints.duplicate()

func _freeze_raider_waypoints() -> void: ##captures the deterministic ordered raid target list for each active spawn before the combat wave begins
	_frozen_raider_waypoints.clear()

	var raider_wall_modes: Dictionary[bool, bool] = {}
	for enemy_stack: Array in _enemies_planned:
		var unit_type: Units.Type = enemy_stack[0]
		if Units.get_unit_route_mode(unit_type) != NavigationComponent.RouteMode.RAIDER_CHAIN:
			continue
		raider_wall_modes[Units.get_unit_ignore_walls(unit_type)] = true

	if raider_wall_modes.is_empty():
		return

	var raid_targets: Array[Tower] = Run.references.island.get_raid_targets()
	for spawn_cell: Vector2i in SpawnPointService.get_spawn_points():
		var waypoint_cells: Array[Vector2i] = RaiderRoutePlanner.get_waypoint_cells_for_spawn(spawn_cell, raid_targets)
		for ignore_walls: bool in raider_wall_modes:
			_frozen_raider_waypoints[_make_raider_waypoint_key(spawn_cell, ignore_walls)] = waypoint_cells.duplicate()

func _make_raider_waypoint_key(spawn_cell: Vector2i, ignore_walls: bool) -> int:
	var combined_coords: int = (int(spawn_cell.y) << 32) | (spawn_cell.x & 0xFFFFFFFF)
	return (combined_coords << 1) | int(ignore_walls)

func _refresh_breach_enemy_assignments() -> void: ##rebuilds per-breach enemy assignments whenever the active breach set changes so previews stay valid through spawn-point churn
	_breach_enemy_assignments.clear()

	if not is_instance_valid(Run.phases):
		return
	if Run.phases.current_wave_number <= 0:
		return

	var active_breaches: Array[Tower] = SpawnPointService.get_active_breaches()
	if active_breaches.is_empty():
		return

	var planned_stacks: Array[Array] = get_planned_enemies_for_wave(Run.phases.current_wave_number)
	if planned_stacks.is_empty():
		return

	var breach_streams: Dictionary[int, Array] = {}
	for breach: Tower in active_breaches:
		if not is_instance_valid(breach):
			continue
		breach_streams[breach.unit_id] = []

	var active_breach_count: int = active_breaches.size()
	var breach_index: int = 0
	for enemy_stack: Array in planned_stacks:
		var unit_type: Units.Type = enemy_stack[0]
		var unit_count: int = int(enemy_stack[1])
		for _stack_index: int in range(unit_count):
			var breach: Tower = active_breaches[breach_index % active_breach_count]
			breach_index += 1
			if not is_instance_valid(breach):
				continue

			var assigned_units: Array[Units.Type]
			assigned_units.assign(breach_streams.get(breach.unit_id, []))
			assigned_units.append(unit_type)
			breach_streams[breach.unit_id] = assigned_units

	for breach: Tower in active_breaches:
		if not is_instance_valid(breach):
			continue
		var assigned_units: Array[Units.Type] = breach_streams.get(breach.unit_id, [])
		_breach_enemy_assignments[breach.unit_id] = WaveEnemies._consolidate_enemy_list(assigned_units)
		UI.update_unit_state.emit(breach)

#the primary, high-frequency update method
func _on_enemy_died(_died_unit: Unit) -> void:
	#do nothing if no combat wave is active (e.g., from a stray signal)
	if current_combat_wave_number == 0:
		return

	_enemies_killed += 1

	#check if the wave is over
	if _enemies_killed >= _enemies_spawned and _enemies_killed >= _total_enemies_planned:
		_end_combat_wave()

#the secondary, low-frequency reconciliation method
func _reconcile_enemy_count() -> void:
	if current_combat_wave_number == 0:
		return

	#get the absolute truth from the scene tree
	var true_count_in_scene: int = get_tree().get_nodes_in_group(ENEMY_GROUP).size()

	#calculate what the system *thinks* should be in the scene
	var expected_count_in_scene: int = _enemies_spawned - _enemies_killed
	#if reality has fewer enemies than expected, it means signals were missed
	if true_count_in_scene < expected_count_in_scene:
		var missed_deaths: int = expected_count_in_scene - true_count_in_scene
		push_warning("Waves: Reconciling enemy count. Missed %d death signals." % missed_deaths)

		_enemies_killed += missed_deaths

		#after correction, check if the wave is now over
		if _enemies_killed >= _total_enemies_planned:
			_end_combat_wave()

#new centralized function to end the combat wave and clean up state
func _end_combat_wave() -> void:
	#guard against multiple calls
	if current_combat_wave_number == 0:
		return

	print("Waves: All enemies cleared for combat wave ", current_combat_wave_number, ". Emitting wave_ended.")

	#clear any remaining enemies from the group in case reconciliation hasn't run
	for enemy: Node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		enemy.queue_free()

	wave_ended.emit(current_combat_wave_number)
	_frozen_raider_waypoints.clear()
	current_combat_wave_number = 0
