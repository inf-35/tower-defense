extends Node
class_name TutorialDirector

signal rite_placed_validly(tower: Tower)

class TutorialRequest extends RefCounted:
	var sequence_id: StringName = StringName()
	var steps: Array[TutorialStep] = []
	var world_target: Tower
	var completion_flag: int = -1

enum OnboardingStage {
	INACTIVE,
	INTRO,
	WAIT_FOR_PAUSE,
	SHOP_POISONS,
	RITE_SELECT_PLACE,
	RITE_REPOSITION,
	WAIT_FOR_EXPANSION,
	RESTOCK_EPIDEMIC,
	COMPLETE,
}

const ONBOARDING_SEQUENCE_IDS: Dictionary = {
	OnboardingStage.INTRO: &"onboarding_intro",
	OnboardingStage.SHOP_POISONS: &"onboarding_shop_poisons",
	OnboardingStage.RITE_SELECT_PLACE: &"onboarding_rite_select_place",
	OnboardingStage.RITE_REPOSITION: &"onboarding_rite_reposition",
	OnboardingStage.RESTOCK_EPIDEMIC: &"onboarding_restock_epidemic",
}

const FOLLOWUP_DELAY: float = 1.0
const POISONS_SHOP_BUY_STEP_INDEX: int = 1
const EPIDEMIC_SHOP_RESTOCK_STEP_INDEX: int = 1
const EPIDEMIC_SHOP_BUY_STEP_INDEX: int = 2
const POISONS_REWARD_PROTOTYPE: RewardPrototype = preload("res://Content/Rewards/Rites/poisons_rite.tres")
const RUPTURED_HEART_REWARD_PROTOTYPE: RewardPrototype = preload("res://Content/Rewards/Relics/ruptured_heart.tres")
const RUINS_TUTORIAL: TutorialStep = preload("res://UI/tutorial/ruins.tres")
const DESTROYED_TOWER_TUTORIAL: TutorialStep = preload("res://UI/tutorial/destroyed_tower.tres")
const TROLL_WARNING_TUTORIAL: TutorialStep = preload("res://UI/tutorial/troll_warning.tres")
const BASIC_TUTORIAL_RITE_TYPES: Array[Towers.Type] = [
	Towers.Type.RITE_BLOOD,
	Towers.Type.RITE_CURSES,
	Towers.Type.RITE_POISONS,
	Towers.Type.RITE_FROST,
	Towers.Type.RITE_FLAME,
]

var _onboarding_stage: OnboardingStage = OnboardingStage.INACTIVE
var _pending_requests: Array[TutorialRequest] = []
var _suspended_requests: Array[TutorialRequest] = []
var _active_request: TutorialRequest
var _tutorial_rite_tower: Tower
var _forced_poisons_reward: Reward
var _forced_ruptured_heart_reward: Reward
var _force_basic_expansion_rites: bool = false
var _runtime_connected: bool = false

func refresh_runtime_connections() -> void: ##binds the presenter and run-scoped event sources once the player services for this run exist
	if _runtime_connected:
		return
	if not is_instance_valid(UI.tutorial_manager):
		return
	if not UI.tutorial_manager.sequence_finished.is_connected(_on_sequence_finished):
		UI.tutorial_manager.sequence_finished.connect(_on_sequence_finished)
	if not Run.phases.wave_cycle_started.is_connected(_on_wave_cycle_started):
		Run.phases.wave_cycle_started.connect(_on_wave_cycle_started)
	if not Run.phases.building_phase_started.is_connected(_on_building_phase_started):
		Run.phases.building_phase_started.connect(_on_building_phase_started)
	if not Run.phases.combat_started.is_connected(_on_combat_started):
		Run.phases.combat_started.connect(_on_combat_started)
	if not Run.player.tower_placed.is_connected(_on_tower_placed):
		Run.player.tower_placed.connect(_on_tower_placed)
	if is_instance_valid(Run.player.trader_service):
		if not Run.player.trader_service.item_purchased.is_connected(_on_trader_item_purchased):
			Run.player.trader_service.item_purchased.connect(_on_trader_item_purchased)
		if not Run.player.trader_service.stock_restocked.is_connected(_on_trader_stock_restocked):
			Run.player.trader_service.stock_restocked.connect(_on_trader_stock_restocked)
	if is_instance_valid(Run.references.island):
		if not Run.references.island.tower_created.is_connected(_on_tower_created):
			Run.references.island.tower_created.connect(_on_tower_created)
		if not Run.references.island.expansion_service.expansion_process_complete.is_connected(_on_expansion_process_complete):
			Run.references.island.expansion_service.expansion_process_complete.connect(_on_expansion_process_complete)
	_runtime_connected = true

func begin_new_game() -> void: ##starts the scripted onboarding if the profile has not fully completed it yet
	_pending_requests.clear()
	_suspended_requests.clear()
	_active_request = null
	_tutorial_rite_tower = null
	_forced_poisons_reward = null
	_forced_ruptured_heart_reward = null
	_force_basic_expansion_rites = false
	refresh_runtime_connections()
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		_onboarding_stage = OnboardingStage.COMPLETE
		return

	_onboarding_stage = OnboardingStage.INTRO
	_force_basic_expansion_rites = true
	_shift_first_expansion()
	Run.phases.wave_schedule_updated.emit()
	_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.INTRO], _build_intro_steps()), false)

func should_force_basic_tutorial_rites() -> bool:
	return _force_basic_expansion_rites

func pick_basic_tutorial_rite_type() -> Towers.Type:
	return BASIC_TUTORIAL_RITE_TYPES.pick_random()

func can_purchase_trader_reward(reward: Reward) -> bool:
	if _onboarding_stage == OnboardingStage.INACTIVE:
		return true
	if Run.phases.current_phase != Run.phases.GamePhase.BUILDING:
		return false
	if not Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING] and _onboarding_stage not in [OnboardingStage.SHOP_POISONS, OnboardingStage.RESTOCK_EPIDEMIC]:
		return false
	match _onboarding_stage:
		OnboardingStage.SHOP_POISONS:
			if not _is_sequence_step_active(ONBOARDING_SEQUENCE_IDS[OnboardingStage.SHOP_POISONS], POISONS_SHOP_BUY_STEP_INDEX):
				return false
			return _matches_forced_reward(reward, _forced_poisons_reward)
		OnboardingStage.RESTOCK_EPIDEMIC:
			if not _is_sequence_step_active(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RESTOCK_EPIDEMIC], EPIDEMIC_SHOP_BUY_STEP_INDEX):
				return false
			return _matches_forced_reward(reward, _forced_ruptured_heart_reward)
	return true

func can_open_trader() -> bool:
	if _onboarding_stage == OnboardingStage.INACTIVE:
		return true
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		return true
	match _onboarding_stage:
		OnboardingStage.SHOP_POISONS:
			return Run.phases.current_phase == Run.phases.GamePhase.BUILDING and Run.phases.current_wave_number == 2
		OnboardingStage.RESTOCK_EPIDEMIC:
			return Run.phases.current_phase == Run.phases.GamePhase.BUILDING and Run.phases.current_wave_number >= 3
	return false

func can_close_trader() -> bool:
	return true

func can_force_restock() -> bool:
	if _onboarding_stage == OnboardingStage.INACTIVE:
		return true
	if Run.phases.current_phase != Run.phases.GamePhase.BUILDING:
		return false
	if _onboarding_stage == OnboardingStage.COMPLETE:
		return true
	if _onboarding_stage != OnboardingStage.RESTOCK_EPIDEMIC:
		return false
	return _is_sequence_step_active(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RESTOCK_EPIDEMIC], EPIDEMIC_SHOP_RESTOCK_STEP_INDEX)

func request_destroyed_tower_tutorial(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	_queue_flag_tutorial(Player.TutorialFlag.TOWER_DESTROYED, [DESTROYED_TOWER_TUTORIAL], tower)

func get_save_data() -> Dictionary:
	return {
		"onboarding_stage": int(_onboarding_stage),
	}

func load_save_data(data: Dictionary) -> void: ##restores only coarse onboarding progress and restarts the relevant scripted step on demand
	_onboarding_stage = int(data.get("onboarding_stage", OnboardingStage.INACTIVE))
	if _onboarding_stage == OnboardingStage.RITE_REPOSITION:
		_onboarding_stage = OnboardingStage.RITE_SELECT_PLACE
	_force_basic_expansion_rites = _onboarding_stage not in [OnboardingStage.INACTIVE, OnboardingStage.COMPLETE, OnboardingStage.RESTOCK_EPIDEMIC]
	refresh_runtime_connections()
	_restore_after_load.call_deferred()

func _restore_after_load() -> void:
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		_onboarding_stage = OnboardingStage.COMPLETE
		return
	match _onboarding_stage:
		OnboardingStage.INTRO:
			_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.INTRO], _build_intro_steps()), false)
		OnboardingStage.SHOP_POISONS:
			if Run.phases.current_phase == Run.phases.GamePhase.BUILDING:
				_start_poisons_shop_sequence()
		OnboardingStage.RITE_SELECT_PLACE:
			_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RITE_SELECT_PLACE], _build_rite_select_place_steps()), false)
		OnboardingStage.RESTOCK_EPIDEMIC:
			if Run.phases.current_phase == Run.phases.GamePhase.BUILDING:
				_start_epidemic_shop_sequence()

func _on_wave_cycle_started(wave_number: int) -> void:
	var planned_enemies: Array[Array] = WaveEnemies.get_enemies_for_wave(wave_number)
	for enemy_stack: Array in planned_enemies:
		if enemy_stack[0] == Units.Type.TROLL:
			_queue_flag_tutorial(Player.TutorialFlag.TROLL, [TROLL_WARNING_TUTORIAL])
			return

func _on_building_phase_started(wave_number: int) -> void:
	match _onboarding_stage:
		OnboardingStage.SHOP_POISONS:
			if wave_number == 2:
				_start_poisons_shop_sequence()
		OnboardingStage.RESTOCK_EPIDEMIC:
			if wave_number >= 3:
				_start_epidemic_shop_sequence()

func _on_combat_started(wave_number: int) -> void:
	if _onboarding_stage != OnboardingStage.WAIT_FOR_PAUSE or wave_number != 1:
		return
	_start_pause_sequence.call_deferred(wave_number)

func _start_pause_sequence(wave_number: int) -> void:
	await get_tree().create_timer(FOLLOWUP_DELAY, false).timeout
	if wave_number != Run.phases.current_wave_number:
		return
	if Run.phases.current_phase != Run.phases.GamePhase.COMBAT_WAVE:
		return
	var step := _load_step("res://UI/tutorial/pause_controls.tres", Clock.speed_changed)
	_queue_request(_make_request(&"onboarding_pause", [step]), true)

func _on_tower_created(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	if tower.type == Towers.Type.RUINS:
		_queue_flag_tutorial(Player.TutorialFlag.RUINS, [RUINS_TUTORIAL])

func _on_tower_placed(tower_type: Towers.Type, tower: Tower) -> void:
	if tower_type != Towers.Type.RITE_POISONS:
		return
	match _onboarding_stage:
		OnboardingStage.RITE_SELECT_PLACE:
			_tutorial_rite_tower = tower
			if _is_valid_onboarding_rite_placement(tower):
				rite_placed_validly.emit(tower)

func _on_expansion_process_complete() -> void:
	if _onboarding_stage != OnboardingStage.WAIT_FOR_EXPANSION:
		return
	_force_basic_expansion_rites = false
	_onboarding_stage = OnboardingStage.RESTOCK_EPIDEMIC

func _on_trader_item_purchased(reward: Reward, _slot_index: int) -> void:
	if reward == _forced_poisons_reward:
		_forced_poisons_reward = null
	elif reward == _forced_ruptured_heart_reward:
		_forced_ruptured_heart_reward = null

func _on_trader_stock_restocked(is_manual: bool) -> void: 
	if not is_manual:
		return
	if _onboarding_stage == OnboardingStage.RESTOCK_EPIDEMIC and is_instance_valid(_forced_ruptured_heart_reward):
		_ensure_flux(_forced_ruptured_heart_reward.price)

func _on_sequence_finished(sequence_id: StringName) -> void:
	if is_instance_valid(_active_request) and _active_request.sequence_id == sequence_id and _active_request.completion_flag >= 0:
		Run.player.completed_tutorials[_active_request.completion_flag] = true
	_active_request = null

	match sequence_id:
		&"onboarding_intro":
			_onboarding_stage = OnboardingStage.WAIT_FOR_PAUSE
		&"onboarding_pause":
			_onboarding_stage = OnboardingStage.SHOP_POISONS
		&"onboarding_shop_poisons":
			_onboarding_stage = OnboardingStage.RITE_SELECT_PLACE
			_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RITE_SELECT_PLACE], _build_rite_select_place_steps()), false)
		&"onboarding_rite_select_place":
			if is_instance_valid(_tutorial_rite_tower):
				_onboarding_stage = OnboardingStage.RITE_REPOSITION
				_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RITE_REPOSITION], [_build_rite_reposition_info_step()], _tutorial_rite_tower), false)
		&"onboarding_rite_reposition":
			_onboarding_stage = OnboardingStage.WAIT_FOR_EXPANSION
		&"onboarding_restock_epidemic":
			_complete_onboarding()

	_resume_next_request()

func _complete_onboarding() -> void:
	_onboarding_stage = OnboardingStage.COMPLETE
	_force_basic_expansion_rites = false
	Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING] = true

func _queue_flag_tutorial(flag: Player.TutorialFlag, steps: Array[TutorialStep], tower: Tower = null) -> void:
	if Run.player.completed_tutorials[flag]:
		return
	if _has_sequence_id(_make_flag_sequence_id(flag)):
		return
	var request := _make_request(_make_flag_sequence_id(flag), steps, tower, flag)
	_queue_request(request, true)

func _queue_request(request: TutorialRequest, interrupt_current: bool) -> void:
	if not is_instance_valid(UI.tutorial_manager):
		return
	if interrupt_current and UI.tutorial_manager.has_active_sequence():
		var suspended_state := UI.tutorial_manager.take_active_sequence_state()
		if is_instance_valid(suspended_state):
			var resumed_request := _make_request(suspended_state.sequence_id, suspended_state.steps, suspended_state.world_target, _get_completion_flag_for_sequence(suspended_state.sequence_id))
			_suspended_requests.append(resumed_request)
		_active_request = null
	if UI.tutorial_manager.has_active_sequence():
		if interrupt_current:
			_pending_requests.push_front(request)
		else:
			_pending_requests.append(request)
		return
	_start_request(request)

func _resume_next_request() -> void:
	if not _pending_requests.is_empty():
		var next_request = _pending_requests.pop_front()
		_start_request(next_request)
		return
	if _suspended_requests.is_empty():
		return
	_start_request(_suspended_requests.pop_back())

func _start_request(request: TutorialRequest) -> void:
	_active_request = request
	if is_instance_valid(request.world_target):
		UI.tutorial_manager.start_world_sequence(request.steps, request.sequence_id, request.world_target)
		return
	UI.tutorial_manager.start_sequence(request.steps, request.sequence_id)

func _start_poisons_shop_sequence() -> void:
	if _player_has_poisons_rite_available():
		_start_poisons_placement_sequence()
		return
	_forced_poisons_reward = POISONS_REWARD_PROTOTYPE.generate_reward()
	Run.player.trader_service.set_tutorial_stock([_forced_poisons_reward], true)
	_ensure_flux(_forced_poisons_reward.price)
	_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.SHOP_POISONS], _build_poisons_shop_steps()), false)

func _start_poisons_placement_sequence() -> void: ##skips the forced trader purchase when the player already owns the onboarding rite and moves directly to the placement lesson
	_forced_poisons_reward = null
	_onboarding_stage = OnboardingStage.RITE_SELECT_PLACE
	_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RITE_SELECT_PLACE], _build_rite_select_place_steps()), false)

func _start_epidemic_shop_sequence() -> void:
	_forced_ruptured_heart_reward = RUPTURED_HEART_REWARD_PROTOTYPE.generate_reward()
	Run.player.trader_service.set_tutorial_next_manual_restock_stock([_forced_ruptured_heart_reward])
	_ensure_flux(Run.player.trader_service.get_restock_cost() + _forced_ruptured_heart_reward.price)
	_queue_request(_make_request(ONBOARDING_SEQUENCE_IDS[OnboardingStage.RESTOCK_EPIDEMIC], _build_epidemic_shop_steps()), false)

func _build_intro_steps() -> Array[TutorialStep]:
	var select_step := _load_step("res://UI/tutorial/select_tower.tres", UI.tower_selected)
	var turret_step := _load_step("res://UI/tutorial/place_turret.tres", Run.player.tower_placed, [Towers.Type.TURRET])
	var palisade_step := _load_step("res://UI/tutorial/place_palisade.tres", Run.player.tower_placed, [Towers.Type.PALISADE])
	var farm_step := _load_step("res://UI/tutorial/place_farm.tres", Run.player.tower_placed, [Towers.Type.FARM])
	var start_wave_step := _load_step("res://UI/tutorial/start_wave.tres", UI.building_phase_ended)
	return [
		load("res://UI/tutorial/pan_camera.tres"),
		load("res://UI/tutorial/zoom_camera.tres"),
		select_step,
		turret_step,
		palisade_step,
		farm_step,
		load("res://UI/tutorial/gold_population_explanation.tres"),
		load("res://UI/tutorial/hover_player_stats.tres"),
		load("res://UI/tutorial/hover_wave_timeline.tres"),
		start_wave_step,
	]

func _build_poisons_shop_steps() -> Array[TutorialStep]:
	return [
		_load_step("res://UI/tutorial/trade.tres", UI.trader_open),
		_load_step("res://UI/tutorial/buy_poisons_rite.tres", Run.player.trader_service.item_purchased, [_forced_poisons_reward]),
	]

func _build_rite_select_place_steps() -> Array[TutorialStep]:
	return [
		_load_step("res://UI/tutorial/rite_select_inventory.tres", UI.tower_option_selected, [Towers.Type.RITE_POISONS]),
		_load_step("res://UI/tutorial/rite_place_initial.tres", rite_placed_validly),
	]

func _build_rite_reposition_info_step() -> TutorialStep: ##shows the reposition explainer after the first successful adjacent placement instead of forcing a second placement cycle
	var step := _load_step("res://UI/tutorial/rite_reposition.tres")
	step.trigger_type = TutorialStep.TriggerType.BEGIN_TRIGGERED
	step.require_confirmation = true
	step.success_text = "%s\n[Q to continue.]" % step.instruction_text
	return step

func _build_epidemic_shop_steps() -> Array[TutorialStep]:
	var open_step := _load_step("res://UI/tutorial/trade.tres", UI.trader_open)
	open_step.instruction_text = "[Open] the trade menu."
	open_step.require_confirmation = false
	return [
		open_step,
		_load_step("res://UI/tutorial/restock_trade.tres", Run.player.trader_service.stock_restocked, [true]),
		_load_step("res://UI/tutorial/buy_epidemic.tres", Run.player.trader_service.item_purchased, [_forced_ruptured_heart_reward]),
	]

func _load_step(path: String, trigger_signal: Signal = Signal(), desired_parameters: Array = []) -> TutorialStep:
	var step: TutorialStep = (load(path) as TutorialStep).duplicate(true)
	step.trigger_signal = trigger_signal
	step.desired_parameters = desired_parameters
	return step

func _make_request(sequence_id: StringName, steps: Array[TutorialStep], world_target: Tower = null, completion_flag: int = -1) -> TutorialRequest:
	var request := TutorialRequest.new()
	request.sequence_id = sequence_id
	request.steps = steps
	request.world_target = world_target
	request.completion_flag = completion_flag
	return request

func _make_flag_sequence_id(flag: Player.TutorialFlag) -> StringName:
	return StringName("flag_%d" % flag)

func _has_sequence_id(sequence_id: StringName) -> bool:
	if is_instance_valid(_active_request) and _active_request.sequence_id == sequence_id:
		return true
	for request: TutorialRequest in _pending_requests:
		if request.sequence_id == sequence_id:
			return true
	for request: TutorialRequest in _suspended_requests:
		if request.sequence_id == sequence_id:
			return true
	return false

func _get_completion_flag_for_sequence(sequence_id: StringName) -> int:
	var sequence_text: String = String(sequence_id)
	if not sequence_text.begins_with("flag_"):
		return -1
	return int(sequence_text.trim_prefix("flag_"))

func _ensure_flux(required_flux: float) -> void:
	if Run.player.flux < required_flux:
		Run.player.flux = required_flux

func _player_has_poisons_rite_available() -> bool:
	return Run.player.get_rite_count(Towers.Type.RITE_POISONS) > 0

func _is_sequence_step_active(sequence_id: StringName, minimum_step_index: int) -> bool: ##keeps scripted shop actions locked until the matching onboarding step is the one currently being shown
	if not is_instance_valid(UI.tutorial_manager):
		return false
	if UI.tutorial_manager.get_active_sequence_id() != sequence_id:
		return false
	return UI.tutorial_manager.get_current_step_index() >= minimum_step_index

func _matches_forced_reward(candidate: Reward, forced_reward: Reward) -> bool:
	if not is_instance_valid(candidate) or not is_instance_valid(forced_reward):
		return false
	if candidate.type != forced_reward.type:
		return false
	match candidate.type:
		Reward.Type.ADD_RITE:
			return candidate.rite_type == forced_reward.rite_type
		Reward.Type.ADD_RELIC:
			return is_instance_valid(candidate.relic) and is_instance_valid(forced_reward.relic) and candidate.relic.type == forced_reward.relic.type
		_:
			return candidate == forced_reward

func _shift_first_expansion() -> void: ##keeps onboarding's first expansion at wave 3; with the normal 3-wave cadence this is a no-op but preserves older saves/configs gracefully
	var wave_two: Phases.Wave = Run.phases.wave_plan.get(2)
	var wave_three: Phases.Wave = Run.phases.wave_plan.get(3)
	if wave_two == null or wave_three == null:
		return
	wave_two.day_events.erase(Phases.DayEvent.EXPANSION)
	if wave_two.day_events.is_empty():
		wave_two.day_events.append(Phases.DayEvent.NONE)
	if not wave_three.day_events.has(Phases.DayEvent.EXPANSION):
		if wave_three.day_events.size() == 1 and wave_three.day_events[0] == Phases.DayEvent.NONE:
			wave_three.day_events.clear()
		wave_three.day_events.append(Phases.DayEvent.EXPANSION)

func _is_valid_onboarding_rite_placement(rite_tower: Tower) -> bool:
	for adjacent_tower: Tower in rite_tower.get_adjacent_towers().values():
		if not is_instance_valid(adjacent_tower):
			continue
		if adjacent_tower.hostile or adjacent_tower.environmental:
			continue
		if adjacent_tower.type in [Towers.Type.PLAYER_CORE, Towers.Type.FARM, Towers.Type.PALISADE, Towers.Type.PALISADE_UPGRADE_1]:
			continue
		return true
	return false
