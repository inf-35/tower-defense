# Phases.gd
extends Node
# state machine for wave/phase progression

# --- signals ---
# this is the authoritative signal that a new wave cycle has begun.
# UI and other systems should listen to this.
signal wave_cycle_started(wave_number: int) #wave cycle started (beginning of day)
signal wave_ended(wave_number: int) #combat wave ended

signal combat_started(wave_number: int) #combat wave started

signal wave_schedule_updated() ## wave schedule updated

# --- game state variables ---
enum GameDifficulty { NORMAL, HARD }
enum GamePhase { IDLE, CHOICE, BUILDING, COMBAT_WAVE, GAME_OVER }
enum DayEvent { NONE, EXPANSION, REWARD_TOWER, REWARD_RELIC}
enum CombatVariant { NORMAL, BOSS, SURGE}

var current_wave_number: int = 0
var current_phase: GamePhase = GamePhase.IDLE
var current_game_difficulty: GameDifficulty

var in_game: bool = false
var is_game_over: bool = false

enum ChoiceType { EXPANSION, REWARD_TOWER, REWARD_RELIC }
var choice_queue: Array[ChoiceType] = []
var current_choice_type: ChoiceType

var wave_plan: Dictionary[int, Wave] = {}
const FINAL_WAVE: int = 16
class Wave: ## internal data container for a specific wave's configuration
	var day_events: Array[DayEvent] = []
	var combat_variant: CombatVariant = CombatVariant.NORMAL
	
# tutorial tracking system
var _troll_spawned: bool = false

const DEBUG_PRINT_REPORTS: bool = true

func _ready() -> void:
	wave_cycle_started.connect(UI.start_wave.emit)
	combat_started.connect(UI.start_combat.emit)
	wave_ended.connect(UI.end_wave.emit)
	wave_schedule_updated.connect(UI.update_wave_schedule.emit)
	
func start_game() -> void:
	Clock.start()
	References.start()
	ClickHandler.start()
	Units.start()
	Player.start()
	SpawnPointService.start()
	TowerNetworkManager.start()
	
	if SaveLoad.has_save_file():
		_report("Starting from save file.")
		SaveLoad.load_game()
	else:
		await References.references_ready
		begin_new_game()
		Player.begin_new_game()

func begin_new_game():
	References.island.generate_new_island()

	current_wave_number = 0
	current_phase = GamePhase.IDLE
	
	wave_plan.clear()
	choice_queue.clear()
	
	is_game_over = false
	
	_report("New game: Starting game flow.")
	_generate_wave_plan()
	
	start_tutorial()
	
	_prepare_for_next_wave_cycle()
	
func start_tutorial():
	var steps: Array[TutorialStep] = [
		preload("res://UI/tutorial/pan_camera.tres"),
		preload("res://UI/tutorial/zoom_camera.tres"),
	]
	
	var select: TutorialStep = preload("res://UI/tutorial/select_tower.tres")
	select.trigger_signal = UI.tower_selected
	select.desired_parameters = []

	var turret: TutorialStep = preload("res://UI/tutorial/place_turret.tres")
	turret.trigger_signal = UI.place_tower_requested
	turret.desired_parameters = [Towers.Type.TURRET]
	
	var gold_population: TutorialStep = preload("res://UI/tutorial/gold_population_explanation.tres")
	var hover_player_stats: TutorialStep = preload("res://UI/tutorial/hover_player_stats.tres")
	
	var timeline: TutorialStep = preload("res://UI/tutorial/hover_wave_timeline.tres")
	
	var start_wave: TutorialStep = preload("res://UI/tutorial/start_wave.tres")
	start_wave.trigger_signal = UI.building_phase_ended
	start_wave.desired_parameters = []
	
	steps.append(select)
	steps.append(turret)
	steps.append(gold_population)
	steps.append(hover_player_stats)
	steps.append(timeline)
	steps.append(start_wave)
	UI.tutorial_manager.start_sequence(steps)

func _generate_wave_plan() -> void:
	_report("generating wave plan.")
	wave_plan = {}
	for i: int in range(1, FINAL_WAVE + 1):
		var wave := Wave.new()
		# determine day event(s)
		if i % Waves.WAVES_PER_EXPANSION_CHOICE == 0:
			wave.day_events.append(DayEvent.EXPANSION)
			
		if i % 2 == 0:
			wave.day_events.append(DayEvent.REWARD_RELIC)
			
		if i % 5 == 0:
			wave.day_events.append(DayEvent.REWARD_TOWER)
			
		## rewards on specific day
		#if i == 1:
			#wave.day_events.append(DayEvent.REWARD_TOWER)
		
		if wave.day_events.is_empty():
			wave.day_events.append(DayEvent.NONE)
	
		# determine combat variant
		if i == 20 or i == 40 or i == FINAL_WAVE:
			wave.combat_variant = CombatVariant.BOSS
		elif i in [7, 13, 19]:
			wave.combat_variant = CombatVariant.SURGE
		else:
			wave.combat_variant = CombatVariant.NORMAL
		
		wave_plan[i] = wave

	wave_schedule_updated.emit()

# called by Waves.gd to determine what to spawn
func get_combat_variant(wave_num: int) -> CombatVariant:
	if wave_plan.has(wave_num):
		return wave_plan[wave_num].combat_variant
	return CombatVariant.NORMAL

# helper to check if a wave has a specific day event (useful for UI timeline)
func has_day_event(wave_num: int, event: DayEvent) -> bool:
	if wave_plan.has(wave_num):
		return wave_plan[wave_num].day_events.has(event)
	return false

func _prepare_for_next_wave_cycle() -> void:
	current_wave_number += 1

	var wave : Wave = wave_plan.get(current_wave_number, Wave.new())
	_report("Preparing for wave cycle " + str(current_wave_number))
	
	# announce the new wave cycle to all listeners (e.g., WaveTimeline)
	wave_cycle_started.emit(current_wave_number)
	# populate choice queue
	choice_queue.clear()
	for event: DayEvent in wave.day_events:
		match event:
			DayEvent.EXPANSION:
				add_choice_to_queue(ChoiceType.EXPANSION)
			DayEvent.REWARD_TOWER:
				add_choice_to_queue(ChoiceType.REWARD_TOWER)
			DayEvent.REWARD_RELIC:
				add_choice_to_queue(ChoiceType.REWARD_RELIC)
	
	var enemies_planned := WaveEnemies.get_enemies_for_wave(current_wave_number)
	for enemy_stack: Array in enemies_planned:
		var type : Units.Type = enemy_stack[0]
		if type == Units.Type.TROLL and not _troll_spawned:
			_troll_spawned = true
			UI.tutorial_manager.start_sequence([preload("res://UI/tutorial/troll_warning.tres")])
			
	if not choice_queue.is_empty():
		var next_choice: ChoiceType = choice_queue.pop_front()
		_start_choice_phase(next_choice)
	else:
		_start_building_phase()
		
	
func add_choice_to_queue(type: ChoiceType) -> void:
	choice_queue.append(type)
	_report("added " + str(ChoiceType.keys()[type]) + " to choice queue.")

# main state progression logic
func _advance_phase():
	match current_phase:
		GamePhase.IDLE:
			_prepare_for_next_wave_cycle()
		GamePhase.CHOICE:
			_start_building_phase()
		GamePhase.BUILDING:
			UI.day_event_ended.emit()
			_start_combat_wave()
		GamePhase.COMBAT_WAVE:
			current_phase = GamePhase.IDLE
			_advance_phase() # go directly to the next cycle prep
		GamePhase.GAME_OVER:
			_report("Game over state.")

# --- choice Phase Logic ---
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

		ChoiceType.REWARD_TOWER:
			RewardService.generate_and_present_choices(3, [Reward.Type.UNLOCK_TOWER])
			
		ChoiceType.REWARD_RELIC:
			RewardService.generate_and_present_choices(3, [Reward.Type.ADD_RELIC, Reward.Type.ADD_RITE])

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

		ChoiceType.REWARD_TOWER, ChoiceType.REWARD_RELIC:
			# likewise
			RewardService.reward_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			RewardService.select_reward(choice_id)

# this is now called by the ExpansionService's signal when it is done
func _on_choice_applied() -> void:
	if current_phase != GamePhase.CHOICE:
		return
	
	_report("a choice has been successfully applied by its handler.")
	# the service is responsible for hiding its own UI, so we don't need to do it here
	if not choice_queue.is_empty(): # go to the next choice if there is one
		UI.day_event_ended.emit()
		var next_choice: ChoiceType = choice_queue.pop_front()
		_start_choice_phase(next_choice)
	else:
		_advance_phase()

# --- Building Phase Logic --- #TODO: implement end of game signal disconnections
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
	combat_started.emit(current_wave_number)
	current_phase = GamePhase.COMBAT_WAVE
	_report("ordering Waves.gd to start combat for wave " + str(current_wave_number))
	
	if is_instance_valid(Waves):
		if Waves.wave_ended.is_connected(_on_combat_wave_ended):
			Waves.wave_ended.disconnect(_on_combat_wave_ended)
		Waves.wave_ended.connect(_on_combat_wave_ended, CONNECT_ONE_SHOT)
		Waves.start_combat_wave(current_wave_number)
	else:
		push_error("Phases: Waves node not found. Cannot start combat wave.")
		current_phase = GamePhase.IDLE
		_advance_phase()

func _on_combat_wave_ended(_wave_number: int) -> void:
	if current_phase != GamePhase.COMBAT_WAVE:
		return
	_report("combat wave " + str(current_wave_number) + " reported as ended by Waves.gd.")
	wave_ended.emit(current_wave_number)
	
	if current_wave_number >= FINAL_WAVE:
		start_game_over(true)
		return
		
	_advance_phase()
	
func start_game_over(is_victory: bool) -> void:
	is_game_over = true
	current_phase = GamePhase.GAME_OVER
	
	UI.display_game_over.emit(is_victory)
	_report("Game over!")
	
func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	
	data["current_wave_number"] = current_wave_number
	data["current_phase"] = current_phase # saves as int (Enum)

	# Dictionary[int, WaveData] -> Dictionary[str(int), Dictionary]
	var plan_export: Dictionary = {}
	for wave_num: int in wave_plan:
		var wave_data: Wave = wave_plan[wave_num]
		var entry: Dictionary = {}
		
		# convert DayEvent enums to int
		entry["day_events"] = wave_data.day_events # array of ints
		entry["combat_variant"] = wave_data.combat_variant # int
		
		plan_export[str(wave_num)] = entry
		
	data["wave_plan"] = plan_export
	
	return data

func load_save_data(data: Dictionary) -> void:
	current_wave_number = int(data.get("current_wave_number", 0))
	current_phase = int(data.get("current_phase", GamePhase.IDLE))
	
	# reconstruct wave plan
	wave_plan.clear()
	var plan_import: Dictionary = data.get("wave_plan", {})
	
	for key: String in plan_import:
		var wave_num = int(key)
		var entry: Dictionary = plan_import[key]
		
		var new_data = Wave.new()
		
		# restore combat variant
		new_data.combat_variant = int(entry.get("combat_variant", CombatVariant.NORMAL))
		
		# restore day events (Array of Ints)
		# JSON arrays load as Array[float], cast back
		var events_raw = entry.get("day_events", [])
		for evt in events_raw:
			new_data.day_events.append(int(evt))
			
		wave_plan[wave_num] = new_data
	
	match current_phase:
		GamePhase.BUILDING:
			_start_building_phase()
		GamePhase.COMBAT_WAVE:
			_start_combat_wave()
		_:
			push_warning("Phases: Loading save, but non-building and non-combat wave phase detected!")
	
	# UI Refresh
	UI.update_wave_schedule.emit()
	UI.start_wave.emit(current_wave_number) #TODO: synchronise the wave system

func _report(str: String) -> void:
	if not DEBUG_PRINT_REPORTS:
		return
	print("Phases: ", str)
