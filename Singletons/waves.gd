# Waves.gd
extends Node #"Service" type singleton, mainly called by Phases

signal wave_started(wave_number_int: int) # Emitted when combat spawning begins
signal wave_ended # Emitted when all enemies of a specific combat session are cleared

var current_combat_wave_number: int = 0 # Tracks the wave number it's currently managing combat for
var alive_enemies: int = 0:
	set(value):
		alive_enemies = value
		# Only emit wave_ended if we are actually in a combat session for a specific wave
		if alive_enemies <= 0 and current_combat_wave_number > 0:
			print("Waves: All enemies cleared for combat wave ", current_combat_wave_number, ". Emitting wave_ended.")
			var ended_wave = current_combat_wave_number # Store before reset
			current_combat_wave_number = 0 # Reset, ready for next combat call
			wave_ended.emit() # No payload needed as Phases knows current_wave_number

# Constants for waves
# Constants for waves
const CONCURRENT_ENEMY_SPAWNS: int = 10
const EXPANSION_BLOCK_SIZE: int = 12
const WAVES_PER_EXPANSION_CHOICE: int = 3 # e.g., expansion before wave 5, 10, etc.
const EXPANSION_CHOICES_COUNT: int = 3
const DELAY_AFTER_BUILDING_PHASE_ENDS: float = 0.5 # Before starting combat

# New function called by Phases.gd to start a combat wave
func start_combat_wave(wave_num_to_spawn: int):
	if current_combat_wave_number > 0:
		push_warning("Waves: start_combat_wave called for wave " + str(wave_num_to_spawn) + 
					 " while already managing combat for wave " + str(current_combat_wave_number) + ". Ignoring new call.")
		return

	if wave_num_to_spawn <= 0:
		push_error("Waves: start_combat_wave called with invalid wave number: " + str(wave_num_to_spawn))
		return

	current_combat_wave_number = wave_num_to_spawn
	print("Waves: Starting combat mechanics for wave " + str(current_combat_wave_number))
	wave_started.emit(current_combat_wave_number) # Announce spawning has begun
	_spawn_enemies_for_current_wave() # Internal spawner

func _spawn_enemies_for_current_wave():
	# get spawn points from the dedicated service
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()

	if spawn_points.is_empty():
		push_warning("Waves: No active breaches found. Cannot spawn enemies.")
		self.alive_enemies = 0
		return

	var enemies_to_spawn: Array = WaveEnemies.get_enemies_for_wave(current_combat_wave_number)
	var enemy_count: int = WaveEnemies.get_enemy_count(enemies_to_spawn)
	var enemy_stagger: float = 0.1

	if enemy_count <= 0:
		self.alive_enemies = 0
		return

	self.alive_enemies = enemy_count
	# ... (stagger logic remains the same) ...

	for enemy_stack: Array in enemies_to_spawn:
		var unit_type: Units.Type = enemy_stack[0]
		var unit_stack: int = enemy_stack[1]
		
		for i: int in unit_stack:
			var unit: Unit = Units.create_unit(unit_type)
			unit.died.connect(_on_enemy_died, CONNECT_ONE_SHOT)
			# we assume island is still valid to be the parent for enemy nodes
			References.island.add_child(unit)
			
			# pick a random spawn point from the list provided by the service
			var spawn_cell: Vector2i = spawn_points.pick_random()
			unit.movement_component.position = Island.cell_to_position(spawn_cell)


			await get_tree().create_timer(enemy_stagger).timeout
		
		await get_tree().create_timer(enemy_stagger * 3).timeout

func _on_enemy_died():
	if self.alive_enemies > 0:
		self.alive_enemies -= 1 # Setter handles emitting wave_ended
