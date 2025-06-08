# Phases.gd
extends Node
#state machine for wave/phase progression
# --- Game State Variables ---
var current_wave_number: int = 0 # Phases now owns the wave progression

enum GamePhase { IDLE, EXPANSION, BUILDING, COMBAT_WAVE, GAME_OVER }
var current_phase: GamePhase = GamePhase.IDLE

# --- Constants ---
const EXPANSION_BLOCK_SIZE = 12
const WAVES_PER_EXPANSION_CHOICE = 2 # e.g., expansion before wave 5, 10, etc.
const EXPANSION_CHOICES_COUNT: int = 3
const DELAY_AFTER_BUILDING_PHASE_ENDS: float = 0.5 # Before starting combat

const DEBUG_PRINT_REPORTS: bool = true #debug -> print phase reports?

func _ready():
	# Start the game flow
	start_game.call_deferred()

func _report(str: String): #allows us to easily silence reports
	if not DEBUG_PRINT_REPORTS:
		return
		
	print("Phases: ", str)

func start_game():
	_report("Starting game flow.")
	current_wave_number = 0 # Reset or initialize
	# The first action will be to prepare for wave 1.
	# According to new flow: Expansion (if wave 1 is expansion trigger) -> Build -> Combat
	_prepare_for_next_wave_cycle()

# Main state progression logic
func _advance_phase():
	match current_phase:
		GamePhase.IDLE:
			# This state might be used for game over or initial setup
			_report("In IDLE state.")
			# For now, after IDLE (like after combat ends), we prepare next cycle.
			_prepare_for_next_wave_cycle() #goes to either expansion or building

		GamePhase.EXPANSION:
			_report("Expansion phase successfully completed for wave " + str(current_wave_number) + ". Moving to Building phase.")
			_start_building_phase() # Next is building phase

		GamePhase.BUILDING:
			_report("Building phase successfully completed for wave " + str(current_wave_number) + ". Moving to Combat phase.")
			_start_combat_wave() # Next is combat

		GamePhase.COMBAT_WAVE:
			current_phase = GamePhase.IDLE 
			_prepare_for_next_wave_cycle() # Redundant if _on_combat_wave_ended works, safety.

		GamePhase.GAME_OVER:
			_report("Game Over state.")
			# Handle game over UI, etc.

func _prepare_for_next_wave_cycle():
	current_wave_number += 1
	_report("Preparing for wave cycle " + str(current_wave_number))

	if current_wave_number > 0 and current_wave_number % WAVES_PER_EXPANSION_CHOICE == 0:
		_start_expansion_phase() #divert to expansion phase
	else:
		_start_building_phase()

# --- Expansion Phase Logic ---
func _start_expansion_phase():
	current_phase = GamePhase.EXPANSION
	_report("Starting Expansion Phase for upcoming wave " + str(current_wave_number))
	
	var options: Array[ExpansionChoice] = []
	for i: int in EXPANSION_CHOICES_COUNT:
		var new_block_data: Dictionary = TerrainGen.generate_block(EXPANSION_BLOCK_SIZE)
		if new_block_data.is_empty():
			push_warning("Phases: TerrainGen.generate_block returned empty for expansion option " + str(i) + " for wave " + str(current_wave_number))
		
		var choice = ExpansionChoice.new(i, new_block_data) # Use string ID
		options.append(choice)
	
	if options.is_empty():
		push_warning("Phases: All generated expansion options are empty for wave " + str(current_wave_number) + ". Skipping expansion.")
		# If expansion fails, proceed to the next logical step (Building Phase)
		_advance_phase() # This will move from EXPANSION to BUILDING
		return

	if not is_instance_valid(References.island):
		push_error("Phases: Island is not valid when trying to present expansion choices.")
		_advance_phase() # Try to recover by moving to next phase
		return
	
	UI.expansion_selected.connect(_on_player_chose_expansion, CONNECT_ONE_SHOT) #now await player_chose_expansion...
	References.island.present_expansion_choices(options)
	UI.display_expansion_choices.emit(options) # To UI

#see above: responds to player selecting expansion on UI
func _on_player_chose_expansion(choice_id: int): # Ensure UI sends choice ID
	if current_phase != GamePhase.EXPANSION:
		push_warning("Phases: Player chose expansion, but not in Expansion phase.")
		return
	
	_report("Player chose expansion ID: " + str(choice_id) + " for wave " + str(current_wave_number))
	if not is_instance_valid(References.island):
		push_error("Phases: Island is not valid when player chose expansion.")
		# Even if island is invalid, we need to advance the phase to avoid stall
		_advance_phase() 
		return
		
	References.island.expansion_applied.connect(_on_island_expansion_applied, CONNECT_ONE_SHOT)
	References.island.select_expansion(choice_id)

func _on_island_expansion_applied():
	if current_phase != GamePhase.EXPANSION:
		# This might happen if an old signal fires, or state is already advanced.
		# push_warning("Phases: _on_island_expansion_applied received, but not in Expansion phase. Current phase: " + str(current_phase))
		return
	_report("Island expansion applied by Island.gd for wave " + str(current_wave_number) + ".")
	UI.hide_expansion_choices.emit()
	_advance_phase() # Moves from EXPANSION to BUILDING

# --- Building Phase Logic ---
func _start_building_phase():
	current_phase = GamePhase.BUILDING
	_report("Starting Building Phase for wave " + str(current_wave_number))
	UI.show_building_ui.emit() # UI listens to this
	UI.building_phase_ended.connect(_on_player_ended_building_phase, CONNECT_ONE_SHOT) #ui hooks to this
	get_tree().create_timer(0.5).timeout.connect(func():
		UI.building_phase_ended.emit()
	)

# Called by your UI when the player clicks the "End Building Phase" button
func _on_player_ended_building_phase():
	if current_phase != GamePhase.BUILDING:
		push_warning("Phases: Player ended building phase, but not in Building phase.")
		return
	_report("Player ended Building Phase for wave " + str(current_wave_number) + ".")
	UI.hide_building_ui.emit()
	# Add delay before starting combat
	await get_tree().create_timer(DELAY_AFTER_BUILDING_PHASE_ENDS).timeout
	_advance_phase() # Moves from BUILDING to COMBAT

# --- Combat Wave Logic ---
func _start_combat_wave():
	current_phase = GamePhase.COMBAT_WAVE
	_report("Ordering Waves.gd to start combat for wave " + str(current_wave_number))
	if is_instance_valid(Waves):
		Waves.start_combat_wave(current_wave_number) # New function in Waves.gd
		Waves.wave_ended.connect(_on_combat_wave_ended, CONNECT_ONE_SHOT)
	else:
		push_error("Phases: Waves node not found. Cannot start combat wave.")
		current_phase = GamePhase.IDLE # Try to recover or go to error state
		_advance_phase()

func _on_combat_wave_ended(): # Connected to Waves.wave_ended
	if current_phase != GamePhase.COMBAT_WAVE:
		# This could happen if wave_ended is emitted multiple times or late
		# push_warning("Phases: _on_combat_wave_ended received, but not in Combat Wave phase. Current phase: " + str(current_phase))
		return
	_report("Combat wave " + str(current_wave_number) + " reported as ended by Waves.gd.")
	current_phase = GamePhase.IDLE # Reset before preparing next cycle
	_advance_phase() # Will call _prepare_for_next_wave_cycle
