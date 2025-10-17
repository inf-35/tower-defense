# Phases.gd
extends Node
#state machine for wave/phase progression

# --- signals ---
# this is the authoritative signal that a new wave cycle has begun.
# UI and other systems should listen to this.
signal wave_cycle_started(wave_number: int) #wave cycle started
signal wave_ended(wave_number: int) #combat wave ended

# --- game state variables ---
var current_wave_number: int = 0

enum GamePhase { IDLE, CHOICE, BUILDING, COMBAT_WAVE, GAME_OVER }
enum ChoiceType { EXPANSION, REWARD }
var current_phase: GamePhase = GamePhase.IDLE
var choice_queue: Array[ChoiceType] = []
var current_choice_type: ChoiceType

enum WaveType { NORMAL, BOSS, REWARD, SURGE, EXPANSION }
var wave_plan: Dictionary[int, WaveType] = {}
const FINAL_WAVE: int = 50

const DEBUG_PRINT_REPORTS: bool = true

func _ready() -> void:
	start_game.call_deferred()
	wave_cycle_started.connect(UI.start_wave.emit) #connect the systems-side signal to the ui-side signal

func start_game() -> void:
	_report("starting game flow.")
	_generate_wave_plan()
	current_wave_number = 0
	_prepare_for_next_wave_cycle()

func _generate_wave_plan() -> void:
	_report("generating wave plan.")
	wave_plan = {}
	for i: int in range(1, FINAL_WAVE + 1):
		wave_plan[i] = WaveType.NORMAL
		if i % Waves.WAVES_PER_EXPANSION_CHOICE == 0:
			wave_plan[i] = WaveType.EXPANSION
		if i == 20:
			wave_plan[i] = WaveType.BOSS
		if i in [7, 13, 19]:
			wave_plan[i] = WaveType.SURGE
	
	UI.update_wave_schedule.emit() # this signal is fine for a static UI display

# safely get the type of a wave from the plan
func get_wave_type(wave_num: int) -> WaveType:
	return wave_plan.get(wave_num, WaveType.NORMAL)

func _prepare_for_next_wave_cycle() -> void:
	current_wave_number += 1
	_report("preparing for wave cycle " + str(current_wave_number))
	
	# announce the new wave cycle to all listeners (e.g., WaveTimeline)
	wave_cycle_started.emit(current_wave_number)

	var upcoming_wave_type: WaveType = get_wave_type(current_wave_number)
	_report("wave " + str(current_wave_number) + " is of type: " + WaveType.keys()[upcoming_wave_type])

	# queue choices based on the plan.
	match upcoming_wave_type:
		WaveType.REWARD:
			add_choice_to_queue(ChoiceType.REWARD)
		WaveType.EXPANSION:
			add_choice_to_queue(ChoiceType.EXPANSION)

	if not choice_queue.is_empty():
		var next_choice: ChoiceType = choice_queue.pop_front()
		_start_choice_phase(next_choice)
	else:
		_start_building_phase()

# Main state progression logic
func _advance_phase():
	match current_phase:
		GamePhase.IDLE:
			_prepare_for_next_wave_cycle()
		GamePhase.CHOICE:
			_start_building_phase()
		GamePhase.BUILDING:
			_start_combat_wave()
		GamePhase.COMBAT_WAVE:
			current_phase = GamePhase.IDLE
			_advance_phase() # go directly to the next cycle prep
		GamePhase.GAME_OVER:
			_report("game over state.")

# --- Choice Phase Logic ---
func _start_choice_phase(type: ChoiceType) -> void:
	current_phase = GamePhase.CHOICE
	current_choice_type = type
	_report("starting choice phase of type: " + str(ChoiceType.keys()[type]))

	# connect to the generic UI signal for when the player clicks an option
	UI.choice_selected.connect(_on_player_made_choice, CONNECT_ONE_SHOT)

	match type:
		ChoiceType.EXPANSION:
			# delegate the entire expansion process to the ExpansionService.
			# phases.gd should not know how expansions are generated or presented.
			ExpansionService.generate_and_present_choices(
				References.island,
				Waves.EXPANSION_BLOCK_SIZE,
				Waves.EXPANSION_CHOICES_COUNT
			)

		ChoiceType.REWARD:
			RewardService.generate_and_present_choices(3)

# responds to the player selecting an option on the UI
func _on_player_made_choice(choice_id: int) -> void:
	if current_phase != GamePhase.CHOICE:
		return
	
	_report("player chose option id: " + str(choice_id))

	match current_choice_type:
		ChoiceType.EXPANSION:
			# delegate the selection logic to the ExpansionService.
			# we then wait for the service to tell us when the entire process is finished.
			ExpansionService.expansion_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			ExpansionService.select_expansion(References.island, choice_id)

		ChoiceType.REWARD:
			# likewise
			RewardService.reward_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			RewardService.select_reward(choice_id)

func add_choice_to_queue(type: ChoiceType) -> void:
	choice_queue.append(type)
	_report("added " + str(ChoiceType.keys()[type]) + " to choice queue.")

# this is now called by the ExpansionService's signal when it is done
func _on_choice_applied() -> void:
	if current_phase != GamePhase.CHOICE:
		return
	_report("a choice has been successfully applied by its handler.")
	# the service is responsible for hiding its own UI, so we don't need to do it here
	_advance_phase()

# --- Building Phase Logic ---
func _start_building_phase() -> void:
	current_phase = GamePhase.BUILDING
	_report("starting building phase for wave " + str(current_wave_number))
	UI.show_building_ui.emit()
	UI.building_phase_ended.connect(_on_player_ended_building_phase, CONNECT_ONE_SHOT)

func _on_player_ended_building_phase() -> void:
	if current_phase != GamePhase.BUILDING:
		return
	_report("player ended building phase for wave " + str(current_wave_number) + ".")
	UI.hide_building_ui.emit()
	await get_tree().create_timer(Waves.DELAY_AFTER_BUILDING_PHASE_ENDS).timeout
	_advance_phase()

# --- Combat Wave Logic ---
func _start_combat_wave() -> void:
	current_phase = GamePhase.COMBAT_WAVE
	_report("ordering Waves.gd to start combat for wave " + str(current_wave_number))
	
	if is_instance_valid(Waves):
		Waves.wave_ended.connect(_on_combat_wave_ended, CONNECT_ONE_SHOT)
		Waves.start_combat_wave(current_wave_number)
	else:
		push_error("Phases: Waves node not found. Cannot start combat wave.")
		current_phase = GamePhase.IDLE
		_advance_phase()

func _on_combat_wave_ended() -> void:
	if current_phase != GamePhase.COMBAT_WAVE:
		return
	_report("combat wave " + str(current_wave_number) + " reported as ended by Waves.gd.")
	wave_ended.emit(current_wave_number)
	current_phase = GamePhase.IDLE
	_advance_phase()

func _report(str: String) -> void:
	if not DEBUG_PRINT_REPORTS:
		return
	print("Phases: ", str)
