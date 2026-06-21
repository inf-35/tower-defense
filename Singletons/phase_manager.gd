#phases.gd
extends Node
class_name Phases
#state machine for wave/phase progression

#--- signals ---
#this is the authoritative signal that a new wave cycle has begun.
#ui and other systems should listen to this.
signal wave_cycle_started(wave_number: int) ##wave cycle started (beginning of day). towers resurrect with this signal
signal wave_ended(wave_number: int) ##combat wave ended (end of night). towers have not yet resurrected. succeeded by wave_cycle_started.
signal phase_advanced()
signal combat_started(wave_number: int) ##combat wave started

signal wave_schedule_updated() ##wave schedule updated
signal guided_rite_placed(tower: Tower) ##fires when the onboarding rite is placed beside a valid allied tower

#--- game state variables ---
enum GamePhase { IDLE, CHOICE, BUILDING, COMBAT_WAVE, GAME_OVER }
enum DayEvent { NONE, EXPANSION, REWARD_TOWER, REWARD_RELIC}
enum CombatVariant { NORMAL, BOSS, SURGE}

var current_wave_number: int = 0:
	set(ncwm):
		current_wave_number = ncwm
		var base_scaling: float = 0.8 if Run.current_game_difficulty == Run.GameDifficulty.NORMAL else 1.0
		var scaling: float = 0.03 if Run.current_game_difficulty == Run.GameDifficulty.NORMAL else 0.04
		var goal: float = base_scaling + (max(current_wave_number - 12, 0) * scaling)
		Run.current_game_scaling = max(Run.current_game_scaling - 0.1, goal)

var current_phase: GamePhase = GamePhase.IDLE

var in_game: bool = false
var is_game_over: bool = false

enum ChoiceType { EXPANSION, REWARD_TOWER, REWARD_RELIC }
var choice_queue: Array[ChoiceType] = []
var current_choice_type: ChoiceType

var wave_plan: Dictionary[int, Wave] = {}
const FINAL_WAVE: int = 24
class Wave: ##internal data container for a specific wave's configuration
	var day_events: Array[DayEvent] = []
	var combat_variant: CombatVariant = CombatVariant.NORMAL

#tutorial tracking system
var _troll_spawned: bool = false
var _awaiting_guided_rite_from_expansion: bool = false
var _guided_rite_tower: Tower
var _guided_rite_type: Towers.Type = Towers.Type.VOID

const TUTORIAL_FOLLOWUP_DELAY: float = 2.0
const BASIC_TUTORIAL_RITE_TYPES: Array[Towers.Type] = [
	Towers.Type.RITE_BLOOD,
	Towers.Type.RITE_CURSES,
	Towers.Type.RITE_POISONS,
	Towers.Type.RITE_FROST,
	Towers.Type.RITE_FLAME,
]

const DEBUG_PRINT_REPORTS: bool = true

func _ready() -> void:
	wave_cycle_started.connect(UI.start_wave.emit)
	wave_cycle_started.connect(_emit_wave_prep_event)
	combat_started.connect(UI.start_combat.emit)
	wave_ended.connect(UI.end_wave.emit)
	wave_schedule_updated.connect(UI.update_wave_schedule.emit)
	Run.player.tower_placed.connect(_on_tower_placed)

func _emit_wave_prep_event(wave: int) -> void:
	var wave_data := WaveData.new()
	wave_data.wave = wave

	var event := GameEvent.new()
	event.event_type = GameEvent.EventType.WAVE_PREP_STARTED
	event.data = wave_data

	Run.player.on_event.emit(null, event)

func start_game(progress_callback: Callable = Callable()) -> void:
	_report_loading(progress_callback, "Preparing references...", 0.08)
	await get_tree().process_frame
	Clock.start()
	Run.references.start()
	ClickHandler.start()

	_report_loading(progress_callback, "Loading enemy data...", 0.16)
	await get_tree().process_frame
	Units.start()

	_report_loading(progress_callback, "Preparing towers...", 0.24)
	await Towers.start_async(progress_callback)

	_report_loading(progress_callback, "Starting services...", 0.6)
	Run.player.start()
	SpawnPointService.start()
	TowerNetworkManager.start()
	Run.references.start()

	Run.current_game_scaling = 1.0
	Run.current_game_environment = Run.GameEnvironment.WOODS
	await get_tree().process_frame
	if SaveLoad.has_save_file():
		_report_loading(progress_callback, "Loading save...", 0.7)
		_report("Starting from save file.")
		SaveLoad.load_game()
	else:

		await begin_new_game(progress_callback)
		Run.player.begin_new_game()

func begin_new_game(progress_callback: Callable = Callable()) -> void:
	_report_loading(progress_callback, "Loading profile...", 0.62)
	await get_tree().process_frame
	SaveLoad.load_profile()
	await Run.references.island.generate_new_island()
	if not Run.references.island.tower_created.is_connected(_on_tower_created):
		Run.references.island.tower_created.connect(_on_tower_created)
	current_wave_number = 0
	current_phase = GamePhase.IDLE

	wave_plan.clear()
	choice_queue.clear()

	is_game_over = false
	_guided_rite_tower = null
	_guided_rite_type = Towers.Type.VOID
	_awaiting_guided_rite_from_expansion = false

	_report("New game: Starting game flow.")
	_generate_wave_plan()

	start_tutorial()

	_prepare_for_next_wave_cycle()

func _report_loading(progress_callback: Callable, message: String, progress: float) -> void:
	if progress_callback.is_valid():
		progress_callback.call(message, progress)

func start_tutorial() -> void:
	var steps: Array[TutorialStep] = [
		load("res://UI/tutorial/pan_camera.tres"),
		load("res://UI/tutorial/zoom_camera.tres"),
	]

	var select: TutorialStep = load("res://UI/tutorial/select_tower.tres")
	select.trigger_signal = UI.tower_selected
	select.desired_parameters = []

	var turret: TutorialStep = load("res://UI/tutorial/place_turret.tres")
	turret.trigger_signal = Run.player.tower_placed
	turret.desired_parameters = [Towers.Type.TURRET]

	var palisade: TutorialStep = load("res://UI/tutorial/place_palisade.tres")
	palisade.trigger_signal = Run.player.tower_placed
	palisade.desired_parameters = [Towers.Type.PALISADE]

	var farm: TutorialStep = load("res://UI/tutorial/place_farm.tres")
	farm.trigger_signal = Run.player.tower_placed
	farm.desired_parameters = [Towers.Type.FARM]

	var gold_population: TutorialStep = load("res://UI/tutorial/gold_population_explanation.tres")
	var hover_player_stats: TutorialStep = load("res://UI/tutorial/hover_player_stats.tres")
	var trade: TutorialStep = load("res://UI/tutorial/trade.tres")
	trade.trigger_signal = UI.trader_open
	trade.desired_parameters = []
	var timeline: TutorialStep = load("res://UI/tutorial/hover_wave_timeline.tres")

	var start_wave: TutorialStep = load("res://UI/tutorial/start_wave.tres")
	start_wave.trigger_signal = UI.building_phase_ended
	start_wave.desired_parameters = []

	steps.append(select)
	steps.append(turret)
	steps.append(palisade)
	steps.append(farm)
	steps.append(gold_population)
	steps.append(hover_player_stats)
	steps.append(trade)
	steps.append(timeline)
	steps.append(start_wave)
	UI.tutorial_manager.start_sequence(steps, Player.TutorialFlag.MAIN)

func _generate_wave_plan() -> void:
	_report("generating wave plan.")
	wave_plan = {}
	for i: int in range(1, FINAL_WAVE + 1):
		var wave := Wave.new()
		#determine day event(s)
		if i % Run.waves.WAVES_PER_EXPANSION_CHOICE == 0:
			wave.day_events.append(DayEvent.EXPANSION)

		#if i % 2 == 0:
			#wave.day_events.append(DayEvent.REWARD_RELIC)

		#if i % 5 == 0:
			#wave.day_events.append(DayEvent.REWARD_TOWER)

		##rewards on specific day
		#if i == 1:
			#wave.day_events.append(DayEvent.REWARD_TOWER)

		if wave.day_events.is_empty():
			wave.day_events.append(DayEvent.NONE)

		#determine combat variant
		if i == 20 or i == 40 or i == FINAL_WAVE:
			wave.combat_variant = CombatVariant.BOSS
		elif i in [7, 13, 19]:
			wave.combat_variant = CombatVariant.SURGE
		else:
			wave.combat_variant = CombatVariant.NORMAL

		wave_plan[i] = wave

	wave_schedule_updated.emit()

#called by waves.gd to determine what to spawn
func get_combat_variant(wave_num: int) -> CombatVariant:
	if wave_plan.has(wave_num):
		return wave_plan[wave_num].combat_variant
	return CombatVariant.NORMAL

#helper to check if a wave has a specific day event (useful for ui timeline)
func has_day_event(wave_num: int, event: DayEvent) -> bool:
	if wave_plan.has(wave_num):
		return wave_plan[wave_num].day_events.has(event)
	return false

func _prepare_for_next_wave_cycle() -> void:
	current_wave_number += 1

	var wave: Wave = wave_plan.get(current_wave_number, Wave.new())
	_report("Preparing for wave cycle " + str(current_wave_number))

	#announce the new wave cycle to all listeners (e.g., wavetimeline)
	wave_cycle_started.emit(current_wave_number)
	#populate choice queue
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
		var type: Units.Type = enemy_stack[0]
		if type == Units.Type.TROLL and not _troll_spawned:
			_troll_spawned = true
			UI.tutorial_manager.start_sequence([load("res://UI/tutorial/troll_warning.tres")], Run.player.TutorialFlag.TROLL)

	if not choice_queue.is_empty():
		var next_choice: ChoiceType = choice_queue.pop_front()
		_start_choice_phase(next_choice)
	else:
		_start_building_phase()


func add_choice_to_queue(type: ChoiceType) -> void:
	choice_queue.append(type)
	_report("added " + str(ChoiceType.keys()[type]) + " to choice queue.")

#main state progression logic
func _advance_phase() -> void:
	match current_phase:
		GamePhase.IDLE:
			_prepare_for_next_wave_cycle()
		GamePhase.CHOICE:
			_start_building_phase()
		GamePhase.BUILDING:
			_start_combat_wave()
		GamePhase.COMBAT_WAVE:
			current_phase = GamePhase.IDLE
			_advance_phase() #go directly to the next cycle prep
		GamePhase.GAME_OVER:
			_report("Game over state.")
	phase_advanced.emit()

#--- choice phase logic ---
func _start_choice_phase(type: ChoiceType) -> void:
	current_phase = GamePhase.CHOICE
	current_choice_type = type
	_report("starting choice phase of type: " + str(ChoiceType.keys()[type]))
	UI.start_phase.emit(current_wave_number, false, current_choice_type + 1)
	#current_choice_type and day_event (which is the desired output type) are offset by 1, since NONE is the first entry of DayEvent

	#connect to the generic ui signal for when the player clicks an option
	UI.choice_selected.connect(_on_player_made_choice, CONNECT_ONE_SHOT)

	match type:
		ChoiceType.EXPANSION:
			_prepare_guided_rite_capture()
			#delegate the entire expansion process to the expansionservice.
			#phases.gd should not know how expansions are generated or presented.
			Run.references.island.expansion_service.start_expansion_phase()

		ChoiceType.REWARD_TOWER:
			RewardService.generate_and_present_choices(3, [Reward.Type.UNLOCK_TOWER])

		ChoiceType.REWARD_RELIC:
			RewardService.generate_and_present_choices(3, [Reward.Type.ADD_RELIC, Reward.Type.ADD_RITE])

#responds to the player selecting an option on the ui
func _on_player_made_choice(choice_id: int) -> void:
	if current_phase != GamePhase.CHOICE:
		return

	_report("player chose option id: " + str(choice_id))

	match current_choice_type:
		ChoiceType.EXPANSION:
			#delegate the selection logic to the expansionservice.
			#we then wait for the service to tell us when the entire process is finished.
			Run.references.island.expansion_service.expansion_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			#Run.references.island.expansion_service.select_expansion(Run.references.island, choice_id)

		ChoiceType.REWARD_TOWER, ChoiceType.REWARD_RELIC:
			#likewise
			RewardService.reward_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			RewardService.select_reward(choice_id)

#this is now called by the expansionservice's signal when it is done
func _on_choice_applied() -> void:
	if current_phase != GamePhase.CHOICE:
		return

	_report("a choice has been successfully applied by its handler.")
	var should_start_guided_rite_tutorial: bool = current_choice_type == ChoiceType.EXPANSION and _should_start_guided_rite_tutorial()
	#the service is responsible for hiding its own ui, so we don't need to do it here
	if not choice_queue.is_empty(): #go to the next choice if there is one
		UI.day_event_ended.emit()
		var next_choice: ChoiceType = choice_queue.pop_front()
		_start_choice_phase(next_choice)
	else:
		_advance_phase()

	if should_start_guided_rite_tutorial:
		_start_guided_rite_tutorial.call_deferred()

#--- building phase logic ---
func _start_building_phase() -> void:
	current_phase = GamePhase.BUILDING
	UI.start_phase.emit(current_wave_number, false, DayEvent.NONE)
	_report("starting building phase for wave " + str(current_wave_number))
	UI.show_building_ui.emit()
	if not UI.building_phase_ended.is_connected(_on_player_ended_building_phase): #current workaround
		UI.building_phase_ended.connect(_on_player_ended_building_phase, CONNECT_ONE_SHOT)

func _on_player_ended_building_phase() -> void:
	if current_phase != GamePhase.BUILDING:
		return
	_report("player ended building phase for wave " + str(current_wave_number) + ".")
	_maybe_schedule_pause_tutorial(current_wave_number)
	UI.hide_building_ui.emit()
	SaveLoad.save_game()
	await get_tree().create_timer(Run.waves.DELAY_AFTER_BUILDING_PHASE_ENDS).timeout
	_advance_phase()

#--- combat wave logic ---
func _start_combat_wave() -> void:
	combat_started.emit(current_wave_number)
	UI.start_phase.emit(current_wave_number, true, -1)
	current_phase = GamePhase.COMBAT_WAVE
	_report("ordering Run.waves.gd to start combat for wave " + str(current_wave_number))

	if is_instance_valid(Run.waves):
		if Run.waves.wave_ended.is_connected(_on_combat_wave_ended):
			Run.waves.wave_ended.disconnect(_on_combat_wave_ended)
		Run.waves.wave_ended.connect(_on_combat_wave_ended, CONNECT_ONE_SHOT)
		Run.waves.start_combat_wave(current_wave_number)
	else:
		push_error("Phases: Waves node not found. Cannot start combat wave.")
		current_phase = GamePhase.IDLE
		_advance_phase()

func _maybe_schedule_pause_tutorial(wave_number: int) -> void: ##queues the pause tutorial off the start-wave tutorial completion instead of the later combat-start signal
	if wave_number != 1:
		return
	if Run.player.completed_tutorials[Player.TutorialFlag.PAUSE]:
		return
	_schedule_pause_tutorial.call_deferred(wave_number)

func _on_combat_wave_ended(_wave_number: int) -> void:
	if current_phase != GamePhase.COMBAT_WAVE:
		return
	_report("combat wave " + str(current_wave_number) + " reported as ended by Run.waves.gd.")
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
	data["current_phase"] = current_phase #saves as int (enum)

	#dictionary[int, wavedata] -> dictionary[str(int), dictionary]
	var plan_export: Dictionary = {}
	for wave_num: int in wave_plan:
		var wave_data: Wave = wave_plan[wave_num]
		var entry: Dictionary = {}

		#convert dayevent enums to int
		entry["day_events"] = wave_data.day_events #array of ints
		entry["combat_variant"] = wave_data.combat_variant #int

		plan_export[str(wave_num)] = entry

	data["wave_plan"] = plan_export

	return data

func load_save_data(data: Dictionary) -> void:
	current_wave_number = int(data.get("current_wave_number", 0))
	current_phase = int(data.get("current_phase", GamePhase.IDLE))

	#reconstruct wave plan
	wave_plan.clear()
	var plan_import: Dictionary = data.get("wave_plan", {})

	for key: String in plan_import:
		var wave_num = int(key)
		var entry: Dictionary = plan_import[key]

		var new_data = Wave.new()

		#restore combat variant
		new_data.combat_variant = int(entry.get("combat_variant", CombatVariant.NORMAL))

		#restore day events (array of ints)
		#json arrays load as array[float], cast back
		var events_raw = entry.get("day_events", [])
		for evt in events_raw:
			new_data.day_events.append(int(evt))

		wave_plan[wave_num] = new_data

	match current_phase:
		GamePhase.BUILDING:
			_start_building_phase()
		_:
			_start_building_phase()
			push_warning("Phases: Loading save, but non-building and non-combat wave phase detected!")

	#ui refresh
	UI.update_wave_schedule.emit()
	UI.start_wave.emit(current_wave_number)

func _report(str: String) -> void:
	if not DEBUG_PRINT_REPORTS:
		return
	print("Phases: ", str)

func _on_tower_created(tower: Tower) -> void: ##starts the ruin tutorial only when a ruin structure is actually instantiated in the run
	if not is_instance_valid(tower):
		return
	if not is_instance_valid(UI.tutorial_manager):
		return

	if _awaiting_guided_rite_from_expansion and _guided_rite_tower == null and _is_basic_tutorial_rite(tower.type):
		_guided_rite_tower = tower
		_guided_rite_type = tower.type
		return
	if UI.tutorial_manager.visible:
		return

	if Towers.is_tower_rite(tower.type):
		if should_force_basic_tutorial_rites():
			return
		if Run.player.completed_tutorials[Run.player.TutorialFlag.RITE]:
			return
		UI.tutorial_manager.start_world_sequence([load("res://UI/tutorial/rite.tres")], Run.player.TutorialFlag.RITE, tower)
		return

	if tower.type != Towers.Type.RUINS:
		return
	if Run.player.completed_tutorials[Run.player.TutorialFlag.RUINS]:
		return

	UI.tutorial_manager.start_sequence([load("res://UI/tutorial/ruins.tres")], Run.player.TutorialFlag.RUINS)

func should_force_basic_tutorial_rites() -> bool:
	return not Run.player.completed_tutorials[Player.TutorialFlag.RITE]

func pick_basic_tutorial_rite_type() -> Towers.Type:
	return BASIC_TUTORIAL_RITE_TYPES.pick_random()

func _prepare_guided_rite_capture() -> void:
	_guided_rite_tower = null
	_guided_rite_type = Towers.Type.VOID
	_awaiting_guided_rite_from_expansion = should_force_basic_tutorial_rites()

func _should_start_guided_rite_tutorial() -> bool:
	if not _awaiting_guided_rite_from_expansion:
		return false
	_awaiting_guided_rite_from_expansion = false
	return is_instance_valid(_guided_rite_tower) and not Run.player.completed_tutorials[Player.TutorialFlag.RITE]

func _schedule_pause_tutorial(wave_number: int) -> void:
	await get_tree().create_timer(TUTORIAL_FOLLOWUP_DELAY).timeout
	if wave_number != current_wave_number:
		return
	while current_phase != GamePhase.COMBAT_WAVE:
		if wave_number != current_wave_number:
			return
		await get_tree().process_frame
	if Run.player.completed_tutorials[Player.TutorialFlag.PAUSE]:
		return
	while is_instance_valid(UI.tutorial_manager) and UI.tutorial_manager.visible:
		await get_tree().process_frame

	var step: TutorialStep = load("res://UI/tutorial/pause_controls.tres")
	step.trigger_signal = Clock.speed_changed
	step.desired_parameters = []
	UI.tutorial_manager.start_sequence([step], Player.TutorialFlag.PAUSE)

func _start_guided_rite_tutorial() -> void:
	if not is_instance_valid(_guided_rite_tower):
		return
	if Run.player.completed_tutorials[Player.TutorialFlag.RITE]:
		return

	while is_instance_valid(UI.tutorial_manager) and UI.tutorial_manager.visible:
		await get_tree().process_frame

	var select_step: TutorialStep = load("res://UI/tutorial/rite_select.tres")
	select_step.trigger_signal = ClickHandler.tower_was_selected
	select_step.desired_parameters = [_guided_rite_tower]

	var reposition_step: TutorialStep = load("res://UI/tutorial/rite_reposition.tres")
	reposition_step.trigger_signal = Run.player.rite_excavated
	reposition_step.desired_parameters = [_guided_rite_tower]

	var place_step: TutorialStep = load("res://UI/tutorial/rite_place.tres")
	place_step.trigger_signal = guided_rite_placed
	place_step.desired_parameters = []

	UI.tutorial_manager.start_world_sequence(
		[select_step, reposition_step, place_step],
		Player.TutorialFlag.RITE,
		_guided_rite_tower
	)

func _on_tower_placed(tower_type: Towers.Type, tower: Tower) -> void:
	if tower_type != _guided_rite_type:
		return
	if not is_instance_valid(tower):
		return
	if not _is_valid_guided_rite_placement(tower):
		return

	guided_rite_placed.emit(tower)
	_guided_rite_type = Towers.Type.VOID
	_guided_rite_tower = null

func _is_valid_guided_rite_placement(rite_tower: Tower) -> bool:
	for adjacent_tower: Tower in rite_tower.get_adjacent_towers().values():
		if not is_instance_valid(adjacent_tower):
			continue
		if adjacent_tower.hostile or adjacent_tower.environmental:
			continue
		if adjacent_tower.type in [Towers.Type.PLAYER_CORE, Towers.Type.FARM, Towers.Type.PALISADE, Towers.Type.PALISADE_UPGRADE_1]:
			continue
		return true

	return false

func _is_basic_tutorial_rite(tower_type: Towers.Type) -> bool:
	return BASIC_TUTORIAL_RITE_TYPES.has(tower_type)
