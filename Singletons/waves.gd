#extends Node #Waves
#
#signal wave_started(wave_number: int)
#signal offer_expansion_choices()
#
#var wave: int = 0 #current wave number
#var wave_timer : Timer
#
#const EXPANSION_BLOCK_SIZE: int = 8
#const WAVES_PER_EXPANSION: int = 5
#const WAVE_INTERVAL_SECONDS: float = 2.0
#
#func start_wave(wave: int):
	#References.island.spawn_enemies(wave)
	#wave_started.emit(wave)
#
	#
#func _ready():
	#wave_timer = Timer.new()
	#wave_timer.one_shot = true
	#add_child(wave_timer)
	#wave_timer.wait_time = WAVE_INTERVAL_SECONDS
	#wave_timer.timeout.connect(_on_wave_timer_timeout)
	#
	#Expansions
	#
#func _on_wave_timer_timeout():
	#pass

# Waves.gd
extends Node

signal wave_started(wave_number: int)
# New signal to ExpansionManager:
signal offer_expansion_choices(choices: Array[ExpansionChoice])

var wave: int = 0
var wave_timer: Timer

# Assumed expansion block size, can be configured elsewhere
const EXPANSION_BLOCK_SIZE = 12
const WAVES_PER_EXPANSION_CHOICE = 5
const WAVE_INTERVAL_SECONDS = 0.5
const EXPANSION_CHOICES: int = 3

func _ready():
	wave_timer = Timer.new()
	wave_timer.one_shot = false # Timer will be manually restarted after each wave/expansion phase
	add_child(wave_timer)
	wave_timer.wait_time = WAVE_INTERVAL_SECONDS
	wave_timer.timeout.connect(start_next_wave_or_expansion_phase)
	
	# Connect to ExpansionManager to know when the expansion phase is over
	if not Expansions.is_connected("expansion_phase_ended", resume_wave_cycle):
		Expansions.expansion_phase_ended.connect(resume_wave_cycle)

	start_next_wave_or_expansion_phase.call_deferred() # Start the process once scene is ready

func start_next_wave_or_expansion_phase():
	wave += 1
	print("Waves: Starting phase for wave " + str(wave))

	if wave > 0 and wave % WAVES_PER_EXPANSION_CHOICE == 0:
		initiate_expansion_choice_sequence() #expansion
	else:
		# Regular wave
		assert(is_instance_valid(References.island))
		References.island.spawn_enemies(wave)
		wave_started.emit(wave)
		wave_timer.start() # Start timer for the next event

func initiate_expansion_choice_sequence():
	print("Waves: Initiating expansion choice for upcoming wave period (current wave: " + str(wave) + ")")
	wave_timer.stop() # Pause waves until choice is made

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
	References.island.spawn_enemies(wave) # Spawn enemies for the wave that just had an expansion
		
	wave_started.emit(wave)
	wave_timer.start() # Start timer for the next event (wave or another expansion choice)

# Note: The old start_wave(wave_num) is effectively replaced by the logic within 
# start_next_wave_or_expansion_phase() and resume_wave_cycle() for spawning enemies.
# The original start_wave was:
# func start_wave(wave: int):
#	References.island.spawn_enemies(wave)
#	References.island.expand_by_block(8) # This line is removed
#	wave_started.emit(wave)
