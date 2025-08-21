# Phases.gd
extends Node
#state machine for wave/phase progression
# --- Game State Variables ---
var current_wave_number: int = 0 # Phases owns wave progression

enum GamePhase { IDLE, CHOICE, BUILDING, COMBAT_WAVE, GAME_OVER }
enum ChoiceType { EXPANSION, REWARD }
var current_phase: GamePhase = GamePhase.IDLE
# a queue to hold upcoming choice phases, enabling dynamic injection
var choice_queue: Array[ChoiceType] = []
# a variable to track the current choice being made
var current_choice_type: ChoiceType

enum WaveType { NORMAL, BOSS, REWARD, SURGE, EXPANSION }
var wave_plan : Dictionary[int, WaveType] = {}
const FINAL_WAVE : int = 50

const DEBUG_PRINT_REPORTS: bool = true #debug -> print phase reports?

func _ready():
	# Start the game flow
	start_game.call_deferred()

func start_game():
	_report("Starting game flow.")
	current_wave_number = 0 # Reset or initialize
	_generate_wave_plan()
	# The first action will be to prepare for wave 1.
	# According to new flow: Expansion (if wave 1 is expansion trigger) -> Build -> Combat
	_prepare_for_next_wave_cycle()

# generates the sequence of wave events for the entire game
func _generate_wave_plan():
	# this function can be expanded with more complex procedural logic
	_report("Generating wave plan.")
	wave_plan = {} # clear any existing plan
	for i : int in range(1, FINAL_WAVE + 1):
		# default to a normal wave
		wave_plan[i] = WaveType.NORMAL
		#set expansion waves at fixed intervals
		if i % Waves.WAVES_PER_EXPANSION_CHOICE == 0:
			wave_plan[i] = WaveType.EXPANSION
		# set boss waves at fixed intervals
		if i % 5 == 0:
			wave_plan[i] = WaveType.BOSS
		# set reward waves to occur after a boss, for example
		if (i - 1) % 5 == 0 and i > 1:
			wave_plan[i] = WaveType.REWARD
		# override specific waves for surge events
		if i in [7, 13, 19]:
			wave_plan[i] = WaveType.SURGE
	
	UI.update_wave_schedule.emit()

# safely get the type of a wave from the plan
func get_wave_type(wave_num: int) -> WaveType:
	return wave_plan.get(wave_num, WaveType.REWARD)

func _prepare_for_next_wave_cycle():
	current_wave_number += 1
	_report("Preparing for wave cycle " + str(current_wave_number))
	# consult the wave plan to decide the flow
	var upcoming_wave_type: WaveType = get_wave_type(current_wave_number)
	_report("Wave " + str(current_wave_number) + " is of type: " + WaveType.keys()[upcoming_wave_type])
	# queue choices based on the plan
	match upcoming_wave_type:
		WaveType.REWARD:
			add_choice_to_queue(ChoiceType.EXPANSION)
		WaveType.EXPANSION:
			add_choice_to_queue(ChoiceType.EXPANSION)
		#NOTE:add other choice injections here
	# if there is a choice to be made, start that phase
	if not choice_queue.is_empty():
		var next_choice: ChoiceType = choice_queue.pop_front()
		_start_choice_phase(next_choice)
	else: # otherwise, proceed directly to building
		_start_building_phase()

# Main state progression logic
func _advance_phase():
	match current_phase:
		GamePhase.IDLE:
			# This state might be used for game over or initial setup
			_report("In IDLE state.")
			# For now, after IDLE (like after combat ends), we prepare next cycle.
			_prepare_for_next_wave_cycle() #goes to either expansion or building

		GamePhase.CHOICE: #differentiated by ChoiceType
			_report("choice phase completed for wave " + str(current_wave_number) + ". moving to building phase.")
			_start_building_phase()

		GamePhase.BUILDING:
			_report("Building phase successfully completed for wave " + str(current_wave_number) + ". Moving to Combat phase.")
			_start_combat_wave() # Next is combat

		GamePhase.COMBAT_WAVE:
			current_phase = GamePhase.IDLE 
			_prepare_for_next_wave_cycle() # Redundant if _on_combat_wave_ended works, safety.

		GamePhase.GAME_OVER:
			_report("Game Over state.")
			# Handle game over UI, etc.

# --- Choice Phase Logic ---
func _start_choice_phase(type : ChoiceType):
	current_phase = GamePhase.CHOICE
	current_choice_type = type
	_report("starting choice phase of type: " + str(ChoiceType.keys()[type]))

	# connect to a generic signal from the UI
	UI.choice_selected.connect(_on_player_made_choice, CONNECT_ONE_SHOT)

	match type:
		ChoiceType.EXPANSION:
			# this block contains logic for generating expansion choices
			var options: Array[ExpansionChoice] = []
			for i: int in Waves.EXPANSION_CHOICES_COUNT:
				var new_block_data: Dictionary = TerrainGen.generate_block(Waves.EXPANSION_BLOCK_SIZE)
				var choice = ExpansionChoice.new(i, new_block_data)
				options.append(choice)

			if options.is_empty():
				push_warning("Phases: All generated expansion options are empty for wave " + str(current_wave_number) + ". Skipping expansion.")
				_advance_phase() # fail gracefully
				return

			References.island.present_expansion_choices(options)
			UI.display_expansion_choices.emit(options)

		ChoiceType.REWARD:
			# this is the logic for presenting reward choices
			# TODO: generate these rewards from a proper system, not hardcoded
			var reward_options: Array[String] = ["gain 50 flux", "unlock cannon tower", "+5% global damage"]
			#UI.display_reward_choices.emit(reward_options) # asks UI to show a different screen

#see above: responds to player selecting expansion on UI
func _on_player_made_choice(choice_id: int):
	if current_phase != GamePhase.CHOICE:
		push_warning("phases: player made choice, but not in choice phase.")
		return
	
	_report("player chose option id: " + str(choice_id) + " for choice type " + str(ChoiceType.keys()[current_choice_type]))

	match current_choice_type:
		ChoiceType.EXPANSION:
			# this block contains logic from the old _on_player_chose_expansion
			if not is_instance_valid(References.island):
				_advance_phase() # fail gracefully
				return
			
			# the island applying an expansion is not instant, so we must wait
			References.island.expansion_applied.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			References.island.select_expansion(choice_id)

		ChoiceType.REWARD:
			# NOTE: applying rewards is instant, so we don't need to wait for a signal
			# a more complex reward might need a manager and an "_on_choice_applied" signal
			match choice_id:
				0:
					Player.flux += 50
				1:
					Player.unlock_tower(Towers.Type.CANNON)
				2:
					# TODO: implement a global modifier system for this
					pass
			
			UI.hide_reward_choices.emit()
			_advance_phase() # advance immediately

func add_choice_to_queue(type: ChoiceType):
	choice_queue.append(type)
	_report("added " + str(ChoiceType.keys()[type]) + " to choice queue.")

func _on_choice_applied():
	if current_phase != GamePhase.CHOICE:
		return
		
	_report("a choice has been successfully applied by its handler.")
	
	# NOTE: the UI hiding is now specific to the choice type
	match current_choice_type:
		ChoiceType.EXPANSION:
			UI.hide_expansion_choices.emit()
	
	_advance_phase() # move to the next phase in the sequence (building)

# --- Building Phase Logic ---
func _start_building_phase():
	current_phase = GamePhase.BUILDING
	_report("Starting Building Phase for wave " + str(current_wave_number))
	UI.show_building_ui.emit() # UI listens to this
	UI.building_phase_ended.connect(_on_player_ended_building_phase, CONNECT_ONE_SHOT) #ui hooks to this

# Called by your UI when the player clicks the "End Building Phase" button
func _on_player_ended_building_phase():
	if current_phase != GamePhase.BUILDING:
		push_warning("Phases: Player ended building phase, but not in Building phase.")
		return
	_report("Player ended Building Phase for wave " + str(current_wave_number) + ".")
	UI.hide_building_ui.emit()
	# Add delay before starting combat
	await get_tree().create_timer(Waves.DELAY_AFTER_BUILDING_PHASE_ENDS).timeout
	_advance_phase() # Moves from BUILDING to COMBAT

# --- Combat Wave Logic ---
func _start_combat_wave():
	current_phase = GamePhase.COMBAT_WAVE
	_report("Ordering Waves.gd to start combat for wave " + str(current_wave_number))
	
	UI.start_wave.emit(current_wave_number) #start wvae signal triggered
	
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

func _report(str: String): #allows us to easily silence reports
	if not DEBUG_PRINT_REPORTS:
		return
		
	print("Phases: ", str)
