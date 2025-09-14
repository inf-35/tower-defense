# Waves.gd
extends Node #"Service" type singleton, mainly called by Phases

signal wave_started(wave_number_int: int)
signal wave_ended

# --- state ---
var current_combat_wave_number: int = 0
var _total_enemies_planned: int = 0:
	set(nia):
		_total_enemies_planned = nia
var _enemies_spawned: int = 0
var _enemies_killed: int = 0
var _enemies_planned: Array[Array] = []

# --- configuration ---
const CONCURRENT_ENEMY_SPAWNS: int = 10
const EXPANSION_BLOCK_SIZE: int = 12
const WAVES_PER_EXPANSION_CHOICE: int = 5
const EXPANSION_CHOICES_COUNT: int = 4
const DELAY_AFTER_BUILDING_PHASE_ENDS: float = 0.5

# --- reconciliation system ---
const ENEMY_GROUP: StringName = &"active_enemies"
var _reconciliation_timer: Timer

func _ready() -> void:
	_reconciliation_timer = Timer.new()
	add_child(_reconciliation_timer)
	_reconciliation_timer.one_shot = false
	_reconciliation_timer.autostart = true
	_reconciliation_timer.start(3.0)
	_reconciliation_timer.timeout.connect(_reconcile_enemy_count)

# main function called by Phases.gd to start a combat wave
func start_combat_wave(wave_num_to_spawn: int) -> void:
	if current_combat_wave_number > 0:
		push_warning("Waves: start_combat_wave called while another wave is active. Ignoring.")
		return
	if wave_num_to_spawn <= 0:
		push_error("Waves: start_combat_wave called with invalid wave number.")
		return

	current_combat_wave_number = wave_num_to_spawn
	
	### EDITED SECTION START ###
	# reset all counters for the new wave
	_enemies_planned = WaveEnemies.get_enemies_for_wave(current_combat_wave_number)
	_total_enemies_planned = WaveEnemies.get_enemy_count(_enemies_planned)
	_enemies_spawned = 0
	_enemies_killed = 0


	print("Waves: Starting combat for wave %d with %d planned enemies." % [current_combat_wave_number, _total_enemies_planned])
	wave_started.emit(current_combat_wave_number)
	
	if _total_enemies_planned > 0:
		_spawn_enemies_for_current_wave()
	else:
		# if no enemies are planned, end the wave immediately
		_end_combat_wave()

func _spawn_enemies_for_current_wave() -> void:
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	if spawn_points.is_empty():
		push_warning("Waves: No active breaches found. Cannot spawn enemies.")
		_end_combat_wave() # end the wave if we can't spawn anything
		return

	var enemies_to_spawn: Array = _enemies_planned
	var enemy_stagger: float = 5.0 / _total_enemies_planned
	var spawn_point_index: int = 0
	
	for enemy_stack: Array in enemies_to_spawn:
		var unit_type: Units.Type = enemy_stack[0]
		var unit_stack_count: int = enemy_stack[1]
		
		for i: int in unit_stack_count:
			# if a new wave has started while we were spawning, abort
			if current_combat_wave_number == 0:
				return

			var unit: Unit = Units.create_unit(unit_type)
			unit.add_to_group(ENEMY_GROUP)
			unit.died.connect(_on_enemy_died.bind(unit), CONNECT_ONE_SHOT)
			References.island.add_child(unit)
			
			var spawn_cell: Vector2i = spawn_points[spawn_point_index]
			spawn_point_index = (spawn_point_index + 1) % spawn_points.size()
			unit.movement_component.position = Island.cell_to_position(spawn_cell)
			
			# increment the spawned counter only after the unit is created
			_enemies_spawned += 1
			await Clock.await_game_time(enemy_stagger)
		
		await Clock.await_game_time(enemy_stagger * 2)

# the primary, high-frequency update method
func _on_enemy_died(died_unit: Unit) -> void:
	# do nothing if no combat wave is active (e.g., from a stray signal)
	if current_combat_wave_number == 0:
		return
		
	_enemies_killed += 1
	
	# check if the wave is over
	if _enemies_killed >= _total_enemies_planned:
		_end_combat_wave()

# the secondary, low-frequency reconciliation method
func _reconcile_enemy_count() -> void:
	if current_combat_wave_number == 0:
		return
		
	# get the absolute truth from the scene tree
	var true_count_in_scene: int = get_tree().get_nodes_in_group(ENEMY_GROUP).size()
	
	# calculate what the system *thinks* should be in the scene
	var expected_count_in_scene: int = _enemies_spawned - _enemies_killed
	# if reality has fewer enemies than expected, it means signals were missed
	if true_count_in_scene < expected_count_in_scene:
		var missed_deaths: int = expected_count_in_scene - true_count_in_scene
		push_warning("Waves: Reconciling enemy count. Missed %d death signals." % missed_deaths)
		
		_enemies_killed += missed_deaths
		
		# after correction, check if the wave is now over
		if _enemies_killed >= _total_enemies_planned:
			_end_combat_wave()

# new centralized function to end the combat wave and clean up state
func _end_combat_wave() -> void:
	# guard against multiple calls
	if current_combat_wave_number == 0:
		return
		
	print("Waves: All enemies cleared for combat wave ", current_combat_wave_number, ". Emitting wave_ended.")
	
	# clear any remaining enemies from the group in case reconciliation hasn't run
	for enemy: Node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		enemy.queue_free()
		
	wave_ended.emit()
	current_combat_wave_number = 0
