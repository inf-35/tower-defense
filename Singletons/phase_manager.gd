#phases.gd
extends Node
class_name Phases
#state machine for wave/phase progression

signal wave_cycle_started(wave_number: int) ##wave cycle started (beginning of day). towers resurrect with this signal
signal wave_ended(wave_number: int) ##combat wave ended (end of night). towers have not yet resurrected. succeeded by wave_cycle_started.
signal phase_advanced()
signal combat_started(wave_number: int) ##combat wave started
signal building_phase_started(wave_number: int) ##building phase started after any choice sequence has resolved
signal wave_schedule_updated() ##wave schedule updated

enum GamePhase { IDLE, CHOICE, BUILDING, COMBAT_WAVE, GAME_OVER }
enum DayEvent { NONE, EXPANSION, REWARD_TOWER, REWARD_RELIC }
enum CombatVariant { NORMAL, BOSS, SURGE }
enum ChoiceType { EXPANSION, REWARD_TOWER, REWARD_RELIC }

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
var choice_queue: Array[ChoiceType] = []
var current_choice_type: ChoiceType
var wave_plan: Dictionary[int, Wave] = {}

const FINAL_WAVE: int = 24
const DEBUG_PRINT_REPORTS: bool = true

class Wave: ##internal data container for a specific wave's configuration
	var day_events: Array[DayEvent] = []
	var combat_variant: CombatVariant = CombatVariant.NORMAL

func _ready() -> void:
	wave_cycle_started.connect(UI.start_wave.emit)
	wave_cycle_started.connect(_emit_wave_prep_event)
	combat_started.connect(UI.start_combat.emit)
	wave_ended.connect(UI.end_wave.emit)
	wave_schedule_updated.connect(UI.update_wave_schedule.emit)

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
	Run.tutorials.refresh_runtime_connections()

	Run.current_game_scaling = 1.0
	Run.current_game_environment = Run.GameEnvironment.WOODS
	await get_tree().process_frame
	if SaveLoad.has_save_file():
		_report_loading(progress_callback, "Loading save...", 0.7)
		_report("Starting from save file.")
		SaveLoad.load_game()
		return

	await begin_new_game(progress_callback)
	Run.player.begin_new_game()

func begin_new_game(progress_callback: Callable = Callable()) -> void:
	_report_loading(progress_callback, "Loading profile...", 0.62)
	await get_tree().process_frame
	SaveLoad.load_profile()
	await Run.references.island.generate_new_island()
	current_wave_number = 0
	current_phase = GamePhase.IDLE
	wave_plan.clear()
	choice_queue.clear()
	is_game_over = false

	_report("New game: Starting game flow.")
	_generate_wave_plan()
	Run.tutorials.begin_new_game()
	_prepare_for_next_wave_cycle()

func _report_loading(progress_callback: Callable, message: String, progress: float) -> void:
	if progress_callback.is_valid():
		progress_callback.call(message, progress)

func _generate_wave_plan() -> void:
	_report("generating wave plan.")
	wave_plan.clear()
	for i: int in range(1, FINAL_WAVE + 1):
		var wave := Wave.new()
		if i % Run.waves.WAVES_PER_EXPANSION_CHOICE == 0:
			wave.day_events.append(DayEvent.EXPANSION)

		if wave.day_events.is_empty():
			wave.day_events.append(DayEvent.NONE)

		if i == 20 or i == 40 or i == FINAL_WAVE:
			wave.combat_variant = CombatVariant.BOSS
		elif i in [7, 13, 19]:
			wave.combat_variant = CombatVariant.SURGE
		else:
			wave.combat_variant = CombatVariant.NORMAL

		wave_plan[i] = wave

	wave_schedule_updated.emit()

func get_combat_variant(wave_num: int) -> CombatVariant:
	if wave_plan.has(wave_num):
		return wave_plan[wave_num].combat_variant
	return CombatVariant.NORMAL

func has_day_event(wave_num: int, event: DayEvent) -> bool:
	if wave_plan.has(wave_num):
		return wave_plan[wave_num].day_events.has(event)
	return false

func _prepare_for_next_wave_cycle() -> void:
	current_wave_number += 1
	var wave: Wave = wave_plan.get(current_wave_number, Wave.new())
	_report("Preparing for wave cycle " + str(current_wave_number))

	wave_cycle_started.emit(current_wave_number)
	choice_queue.clear()
	for event: DayEvent in wave.day_events:
		match event:
			DayEvent.EXPANSION:
				add_choice_to_queue(ChoiceType.EXPANSION)
			DayEvent.REWARD_TOWER:
				add_choice_to_queue(ChoiceType.REWARD_TOWER)
			DayEvent.REWARD_RELIC:
				add_choice_to_queue(ChoiceType.REWARD_RELIC)

	if not choice_queue.is_empty():
		_start_choice_phase(choice_queue.pop_front())
		return
	_start_building_phase()

func add_choice_to_queue(type: ChoiceType) -> void:
	choice_queue.append(type)
	_report("added " + str(ChoiceType.keys()[type]) + " to choice queue.")

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
			_advance_phase()
		GamePhase.GAME_OVER:
			_report("Game over state.")
	phase_advanced.emit()

func _start_choice_phase(type: ChoiceType) -> void:
	current_phase = GamePhase.CHOICE
	current_choice_type = type
	_report("starting choice phase of type: " + str(ChoiceType.keys()[type]))
	UI.start_phase.emit(current_wave_number, false, current_choice_type + 1)
	UI.choice_selected.connect(_on_player_made_choice, CONNECT_ONE_SHOT)

	match type:
		ChoiceType.EXPANSION:
			Run.references.island.expansion_service.start_expansion_phase()
		ChoiceType.REWARD_TOWER:
			RewardService.generate_and_present_choices(3, [Reward.Type.UNLOCK_TOWER])
		ChoiceType.REWARD_RELIC:
			RewardService.generate_and_present_choices(3, [Reward.Type.ADD_RELIC, Reward.Type.ADD_RITE])

func _on_player_made_choice(choice_id: int) -> void:
	if current_phase != GamePhase.CHOICE:
		return
	_report("player chose option id: " + str(choice_id))

	match current_choice_type:
		ChoiceType.EXPANSION:
			Run.references.island.expansion_service.expansion_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
		ChoiceType.REWARD_TOWER, ChoiceType.REWARD_RELIC:
			RewardService.reward_process_complete.connect(_on_choice_applied, CONNECT_ONE_SHOT)
			RewardService.select_reward(choice_id)

func _on_choice_applied() -> void:
	if current_phase != GamePhase.CHOICE:
		return
	_report("a choice has been successfully applied by its handler.")

	if not choice_queue.is_empty():
		UI.day_event_ended.emit()
		_start_choice_phase(choice_queue.pop_front())
		return
	_advance_phase()

func _start_building_phase() -> void:
	current_phase = GamePhase.BUILDING
	UI.start_phase.emit(current_wave_number, false, DayEvent.NONE)
	_report("starting building phase for wave " + str(current_wave_number))
	building_phase_started.emit(current_wave_number)
	UI.show_building_ui.emit()
	if not UI.building_phase_ended.is_connected(_on_player_ended_building_phase):
		UI.building_phase_ended.connect(_on_player_ended_building_phase, CONNECT_ONE_SHOT)

func _on_player_ended_building_phase() -> void:
	if current_phase != GamePhase.BUILDING:
		return
	_report("player ended building phase for wave " + str(current_wave_number) + ".")
	UI.hide_building_ui.emit()
	SaveLoad.save_game()
	await get_tree().create_timer(Run.waves.DELAY_AFTER_BUILDING_PHASE_ENDS).timeout
	_advance_phase()

func _start_combat_wave() -> void:
	combat_started.emit(current_wave_number)
	UI.start_phase.emit(current_wave_number, true, -1)
	current_phase = GamePhase.COMBAT_WAVE
	_report("ordering Run.waves.gd to start combat for wave " + str(current_wave_number))

	if not is_instance_valid(Run.waves):
		push_error("Phases: Waves node not found. Cannot start combat wave.")
		current_phase = GamePhase.IDLE
		_advance_phase()
		return

	if Run.waves.wave_ended.is_connected(_on_combat_wave_ended):
		Run.waves.wave_ended.disconnect(_on_combat_wave_ended)
	Run.waves.wave_ended.connect(_on_combat_wave_ended, CONNECT_ONE_SHOT)
	Run.waves.start_combat_wave(current_wave_number)

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
	var data: Dictionary = {
		"current_wave_number": current_wave_number,
		"current_phase": current_phase,
	}

	var plan_export: Dictionary = {}
	for wave_num: int in wave_plan:
		var wave_data: Wave = wave_plan[wave_num]
		plan_export[str(wave_num)] = {
			"day_events": wave_data.day_events,
			"combat_variant": wave_data.combat_variant,
		}

	data["wave_plan"] = plan_export
	return data

func load_save_data(data: Dictionary) -> void:
	current_wave_number = int(data.get("current_wave_number", 0))
	current_phase = int(data.get("current_phase", GamePhase.IDLE))

	wave_plan.clear()
	var plan_import: Dictionary = data.get("wave_plan", {})
	for key: String in plan_import:
		var wave_num := int(key)
		var entry: Dictionary = plan_import[key]
		var new_data := Wave.new()
		new_data.combat_variant = int(entry.get("combat_variant", CombatVariant.NORMAL))
		for evt: Variant in entry.get("day_events", []):
			new_data.day_events.append(int(evt))
		wave_plan[wave_num] = new_data

	_start_building_phase()
	if current_phase != GamePhase.BUILDING:
		push_warning("Phases: Loading save, but non-building phase detected.")

	UI.update_wave_schedule.emit()
	UI.start_wave.emit(current_wave_number)

func _report(str: String) -> void:
	if not DEBUG_PRINT_REPORTS:
		return
	print("Phases: ", str)
