# Waves.gd
extends Node

signal wave_started(wave_number: int)
signal wave_ended()
# Signals to Phases:
signal offer_expansion_choices(choices: Array[ExpansionChoice])
signal request_building_phase_start()

var wave: int = 0

#per-wave numbers
var alive_enemies: int = 0:
	set(value):
		alive_enemies = value
		if alive_enemies <= 0 and wave > 0:
			wave_ended.emit()

# Assumed expansion block size, can be configured elsewhere
const EXPANSION_BLOCK_SIZE = 12
const WAVES_PER_EXPANSION_CHOICE = 5
const CONCURRENT_ENEMY_SPAWNS: int = 10
const EXPANSION_CHOICES: int = 3

const DELAY_AFTER_BUILDING_PHASE: float = 0.5

func _ready():
	wave_ended.connect(func():
		print("Waves: wave_ended received for wave ", wave, ". Requesting building phase start.")
		request_building_phase_start.emit() # Tell Phases to start the building phase
	)
	wave_started.connect(func(wave: int):
		spawn_enemies(wave)
	)
	# Connect to Phases to know when the expansion phase is over
	Phases.expansion_phase_ended.connect(resume_wave_cycle)
	Phases.building_phase_ended.connect(func():
		print("Waves: Phases.building_phase_ended received. Preparing next game phase after delay.")
		await get_tree().create_timer(DELAY_AFTER_BUILDING_PHASE).timeout
		start_next_wave_or_expansion_phase()
	)

	initial_game_start.call_deferred() # Start the process once scene is ready

func initial_game_start():
	print("Waves: Initial game start. Requesting first building phase before wave 1.")
	request_building_phase_start.emit()

func start_next_wave_or_expansion_phase():
	wave += 1
	print("Waves: Starting phase for wave " + str(wave))

	if wave > 0 and wave % WAVES_PER_EXPANSION_CHOICE == 0:
		initiate_expansion_choice_sequence() #expansion
	else:
		# Regular wave
		assert(is_instance_valid(References.island))
		wave_started.emit(wave)

func initiate_expansion_choice_sequence():
	print("Waves: Initiating expansion choice for upcoming wave period (current wave: " + str(wave) + ")")
	var options: Array[ExpansionChoice] = []

	for i in EXPANSION_CHOICES: # Generate 3 options
		var new_block_data: Dictionary = {}

		new_block_data = TerrainGen.generate_block(EXPANSION_BLOCK_SIZE)
		if new_block_data.is_empty():
			push_warning("Waves: TerrainGen.generate_block returned empty for option " + str(i))
			# For now, we'll create an option with empty data; Island.gd should handle it.	
		var choice = ExpansionChoice.new(i, new_block_data)
		options.append(choice)
	
	if options.is_empty() or options.all(func(opt): return opt.block_data.is_empty()):
		push_warning("Waves: All generated expansion options are empty. Skipping choice phase.")
		resume_wave_cycle()
		return

	offer_expansion_choices.emit(options) # Signal ExpansionManager with the choices

func resume_wave_cycle():
	print("Waves: Resuming wave cycle. Current wave: " + str(wave))
	# After expansion, the current 'wave' number's enemies can spawn.
	wave_started.emit(wave)

func spawn_enemies(wave: int):
	var unit_sc : PackedScene = preload("res://Units/Enemies/basic_unit.tscn")
	
	var island: Island = References.island
	if island.active_boundary_tiles.is_empty():
		push_warning("No boundary available for spawning!")
		return
	
	var enemies_this_wave: int = wave * 5
	var enemy_stagger: float = (2.0 + log(enemies_this_wave) * 0.5) / enemies_this_wave
	alive_enemies += enemies_this_wave
	
	if enemies_this_wave > 500: #mass spawn as fast as is allowed
		var enemies_spawned: int = 0
		while enemies_spawned <= enemies_this_wave:
			var spawn_concurrent: int = min(enemies_this_wave - enemies_spawned, CONCURRENT_ENEMY_SPAWNS)
			for i: int in spawn_concurrent:
				var unit: Unit = unit_sc.instantiate()
				unit.part_of_wave = true
				island.add_child(unit)
				unit.movement_component.position = Island.cell_to_position(island.active_boundary_tiles.pick_random())
			enemies_spawned += spawn_concurrent
			await get_tree().create_timer(enemy_stagger * spawn_concurrent).timeout
	else:
		for i: int in enemies_this_wave:
			var unit: Unit = unit_sc.instantiate()
			unit.part_of_wave = true
			island.add_child(unit)
			unit.movement_component.position = Island.cell_to_position(island.active_boundary_tiles.pick_random())
			await get_tree().create_timer(enemy_stagger).timeout
