extends Node
class_name TutorialDirector

class TutorialRequest extends RefCounted:
	var sequence_id: StringName = StringName()
	var steps: Array[TutorialStep] = []
	var world_target: Tower
	var completion_flag: int = -1

const INTRO_AUTO_ADVANCE_DELAY: float = 0.8
const RUINS_TUTORIAL: TutorialStep = preload("res://UI/tutorial/ruins.tres")
const DESTROYED_TOWER_TUTORIAL: TutorialStep = preload("res://UI/tutorial/destroyed_tower.tres")
const TROLL_WARNING_TUTORIAL: TutorialStep = preload("res://UI/tutorial/troll_warning.tres")
const RITE_TUTORIAL: TutorialStep = preload("res://UI/tutorial/rite.tres")
const SHOP_SEQUENCE_ID: StringName = &"shop_intro"

var _pending_requests: Array[TutorialRequest] = []
var _active_request: TutorialRequest
var _intro_chapters: Array[TutorialContent.Chapter] = []
var _completed_intro_facts: Dictionary[int, bool] = {}
var _intro_active: bool = false
var _active_chapter_index: int = -1
var _advance_generation: int = 0
var _restored_intro_state: Dictionary = {}

func refresh_runtime_connections() -> void: ##binds the presenter and run-scoped event sources once the current run exists so the intro consumes real gameplay facts instead of polling
	if not is_instance_valid(UI.tutorial_manager):
		return
	if not UI.tutorial_manager.fact_observed.is_connected(_on_fact_observed):
		UI.tutorial_manager.fact_observed.connect(_on_fact_observed)
	if not UI.tutorial_manager.intro_continue_requested.is_connected(_on_intro_continue_requested):
		UI.tutorial_manager.intro_continue_requested.connect(_on_intro_continue_requested)
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
	if not UI.tower_option_selected.is_connected(_on_tower_option_selected):
		UI.tower_option_selected.connect(_on_tower_option_selected)
	if is_instance_valid(Run.references.camera):
		var camera: Camera = Run.references.camera
		if not camera.tutorial_pan_observed.is_connected(_on_camera_panned):
			camera.tutorial_pan_observed.connect(_on_camera_panned)
		if not camera.tutorial_zoom_observed.is_connected(_on_camera_zoomed):
			camera.tutorial_zoom_observed.connect(_on_camera_zoomed)
	if is_instance_valid(Run.references.island) and not Run.references.island.tower_created.is_connected(_on_tower_created):
		Run.references.island.tower_created.connect(_on_tower_created)

func begin_new_game() -> void: ##starts the wave-1 onboarding immediately for fresh profiles and leaves later tutorial requests queued behind it
	_pending_requests.clear()
	_active_request = null
	_completed_intro_facts.clear()
	_intro_active = false
	_active_chapter_index = -1
	_advance_generation = 0
	_build_intro_chapters()
	refresh_runtime_connections()
	if is_instance_valid(UI.tutorial_manager):
		UI.tutorial_manager.clear_intro()
		UI.tutorial_manager.set_start_wave_locked(false)
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		return
	begin_intro_if_needed()

func begin_intro_if_needed() -> void:
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		return
	if _intro_active:
		return
	if not _restored_intro_state.is_empty():
		var restored_facts: Dictionary = _restored_intro_state.get("facts", {})
		_completed_intro_facts = restored_facts.duplicate()
		_active_chapter_index = clampi(int(_restored_intro_state.get("chapter_index", 0)), 0, maxi(_intro_chapters.size() - 1, 0))
		_restored_intro_state.clear()
	else:
		_completed_intro_facts.clear()
		_active_chapter_index = 0
	_intro_active = true
	var intro_hover_targets: Dictionary[int, int] = {}
	for chapter: TutorialContent.Chapter in _intro_chapters:
		for fact: int in chapter.hover_targets:
			intro_hover_targets[fact] = chapter.hover_targets[fact]
	UI.tutorial_manager.set_intro_hover_targets(intro_hover_targets)
	_show_active_chapter()

func is_intro_active() -> bool:
	return _intro_active

func is_start_wave_locked() -> bool:
	if not _intro_active:
		return false
	if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
		return false
	return _intro_chapters[_active_chapter_index].start_wave_locked

func notify_fact(fact: int) -> void: ##records sticky onboarding facts once and advances chapters only when the active chapter's requirements have all been met
	if not _intro_active:
		return
	var fact_id: int = int(fact)
	if _completed_intro_facts.get(fact_id, false):
		return
	_completed_intro_facts[fact_id] = true
	UI.tutorial_manager.set_intro_fact_completed(fact)
	if _is_active_chapter_complete():
		_schedule_chapter_advance()

func queue_contextual_tutorial(sequence_id: StringName, steps: Array[TutorialStep], world_target: Tower = null, completion_flag: int = -1) -> void:
	if completion_flag >= 0 and Run.player.completed_tutorials[completion_flag]:
		return
	if _has_sequence_id(sequence_id):
		return
	var request := TutorialRequest.new()
	request.sequence_id = sequence_id
	request.steps = steps
	request.world_target = world_target
	request.completion_flag = completion_flag
	_pending_requests.append(request)
	if not _intro_active and _active_request == null:
		_start_next_pending_request()

func request_destroyed_tower_tutorial(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	queue_contextual_tutorial(_make_flag_sequence_id(Player.TutorialFlag.TOWER_DESTROYED), [DESTROYED_TOWER_TUTORIAL], tower, Player.TutorialFlag.TOWER_DESTROYED)

func should_force_basic_tutorial_rites() -> bool:
	return false

func pick_basic_tutorial_rite_type() -> Towers.Type:
	return Towers.Type.RITE_PLAGUES

func can_purchase_trader_reward(_reward: Reward) -> bool:
	return true

func can_open_trader() -> bool:
	return true

func can_close_trader() -> bool:
	return true

func can_force_restock() -> bool:
	return true

func get_save_data() -> Dictionary:
	return {
		"intro_active": _intro_active,
		"active_chapter_index": _active_chapter_index,
		"completed_facts": _completed_intro_facts.keys(),
	}

func load_save_data(data: Dictionary) -> void: ##restores only the loose onboarding chapter state; queued contextual hints are intentionally regenerated from runtime events instead of being serialized
	var saved_fact_ids: Array = data.get("completed_facts", [])
	var saved_facts: Dictionary[int, bool] = {}
	for fact_id: Variant in saved_fact_ids:
		saved_facts[int(fact_id)] = true
	_restored_intro_state = {
		"intro_active": bool(data.get("intro_active", false)),
		"chapter_index": int(data.get("active_chapter_index", 0)),
		"facts": saved_facts,
	}
	refresh_runtime_connections()
	_restore_after_load.call_deferred()

func _restore_after_load() -> void:
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		_maybe_queue_shop_intro()
		return
	if bool(_restored_intro_state.get("intro_active", false)):
		begin_intro_if_needed()
		return
	_maybe_queue_shop_intro()

func _build_intro_chapters() -> void:
	_intro_chapters.clear()

	var camera_controls := TutorialContent.Chapter.new()
	camera_controls.id = &"camera_controls"
	camera_controls.anchor = TutorialContent.Anchor.CENTRAL
	camera_controls.checklist_items = [
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.CAMERA_PANNED, "Move the camera with WASD or drag with MMB."),
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.CAMERA_ZOOMED, "Zoom in and out with scroll."),
	]
	_intro_chapters.append(camera_controls)

	var towers := TutorialContent.Chapter.new()
	towers.id = &"towers"
	towers.anchor = TutorialContent.Anchor.TOWER_BAR
	towers.highlight_elements = [TutorialContent.Element.TOWER_BAR]
	towers.checklist_items = [
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.TOWER_BAR_SELECTED, "Select a tower from the tower bar to inspect it."),
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.TURRET_PLACED, "Place a {T_TURRET} down."),
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.FARM_PLACED, "Place down as many {T_FARM|label=Farms} as possible."),
	]
	towers.paragraph_text = "You can place towers to control the paths of enemies. Try to make them as long as possible."
	towers.footer_text = "[Q to continue.]"
	towers.auto_advance = false
	_intro_chapters.append(towers)

	var information := TutorialContent.Chapter.new()
	information.id = &"information"
	information.anchor = TutorialContent.Anchor.PLAYER_STATS
	information.highlight_elements = [
		TutorialContent.Element.PLAYER_STATS,
		TutorialContent.Element.WAVE_TIMELINE,
	]
	information.checklist_items = [
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.PLAYER_STATS_HOVERED, "Hover on the icons in the player stats (top-left)"),
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.WAVE_TIMELINE_HOVERED, "Hover on the icons in the wave timeline (top-right) to see future events"),
	]
	information.paragraph_text = "You can hover on {KEYWORD_TUTORIAL}/icons (i.e. {BLEED}, {BURN}, {GOLD}) within tooltips (including these ones!)"
	information.hover_targets = {
		TutorialContent.Fact.PLAYER_STATS_HOVERED: TutorialContent.Element.PLAYER_STATS,
		TutorialContent.Fact.WAVE_TIMELINE_HOVERED: TutorialContent.Element.WAVE_TIMELINE,
	}
	_intro_chapters.append(information)

	var start_wave := TutorialContent.Chapter.new()
	start_wave.id = &"start_wave"
	start_wave.anchor = TutorialContent.Anchor.START_WAVE
	start_wave.paragraph_text = "Start the wave when you're ready. Towers can still be built mid-battle."
	start_wave.highlight_element = TutorialContent.Element.START_WAVE_BUTTON
	start_wave.start_wave_locked = false
	start_wave.auto_advance = false
	_intro_chapters.append(start_wave)

func _show_active_chapter() -> void:
	if _active_chapter_index >= _intro_chapters.size():
		_complete_intro()
		return
	var chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
	UI.tutorial_manager.set_start_wave_locked(chapter.start_wave_locked)
	UI.tutorial_manager.present_intro_chapter(chapter, _completed_intro_facts)
	if _is_active_chapter_complete():
		_schedule_chapter_advance()

func _is_active_chapter_complete() -> bool:
	if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
		return false
	var chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
	for fact: int in chapter.get_required_facts():
		if not _completed_intro_facts.get(int(fact), false):
			return false
	return true

func _schedule_chapter_advance() -> void:
	var chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
	if not chapter.auto_advance:
		return
	_advance_generation += 1
	var generation: int = _advance_generation
	_advance_intro_after_delay.call_deferred(generation)

func _advance_intro_after_delay(generation: int) -> void:
	await get_tree().create_timer(INTRO_AUTO_ADVANCE_DELAY, false).timeout
	if generation != _advance_generation:
		return
	if not _intro_active:
		return
	if not _is_active_chapter_complete():
		return
	_active_chapter_index += 1
	_show_active_chapter()

func _complete_intro() -> void:
	_intro_active = false
	_active_chapter_index = -1
	UI.tutorial_manager.set_start_wave_locked(false)
	UI.tutorial_manager.clear_intro()
	Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING] = true
	_start_next_pending_request()

func _start_next_pending_request() -> void:
	if _intro_active or _active_request != null or _pending_requests.is_empty():
		return
	_active_request = _pending_requests.pop_front()
	if is_instance_valid(_active_request.world_target):
		UI.tutorial_manager.start_world_sequence(_active_request.steps, _active_request.sequence_id, _active_request.world_target)
		return
	UI.tutorial_manager.start_sequence(_active_request.steps, _active_request.sequence_id)

func _on_sequence_finished(sequence_id: StringName) -> void:
	if is_instance_valid(_active_request) and _active_request.sequence_id == sequence_id and _active_request.completion_flag >= 0:
		Run.player.completed_tutorials[_active_request.completion_flag] = true
	_active_request = null
	_start_next_pending_request()

func _on_fact_observed(fact: int) -> void:
	notify_fact(fact)

func _on_intro_continue_requested() -> void:
	if not _intro_active:
		return
	if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
		return
	var chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
	if chapter.auto_advance:
		return
	if chapter.checklist_items.is_empty():
		return
	if not _is_active_chapter_complete():
		return
	_active_chapter_index += 1
	_show_active_chapter()

func _on_camera_panned() -> void:
	notify_fact(TutorialContent.Fact.CAMERA_PANNED)

func _on_camera_zoomed() -> void:
	notify_fact(TutorialContent.Fact.CAMERA_ZOOMED)

func _on_tower_option_selected(_tower_type: Towers.Type) -> void:
	notify_fact(TutorialContent.Fact.TOWER_BAR_SELECTED)

func _on_tower_placed(_tower_type: Towers.Type, tower: Tower) -> void:
	if not is_instance_valid(tower) or tower.hostile or tower.environmental or tower.abstractive:
		return
	if _tower_type == Towers.Type.TURRET:
		notify_fact(TutorialContent.Fact.TURRET_PLACED)
	if _tower_type == Towers.Type.FARM:
		notify_fact(TutorialContent.Fact.FARM_PLACED)

func _on_combat_started(_wave_number: int) -> void:
	notify_fact(TutorialContent.Fact.WAVE_STARTED)
	if not _intro_active:
		return
	if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
		return
	if _intro_chapters[_active_chapter_index].id != &"start_wave":
		return
	_complete_intro()

func _on_wave_cycle_started(wave_number: int) -> void:
	var planned_enemies: Array[Array] = WaveEnemies.get_enemies_for_wave(wave_number)
	for enemy_stack: Array in planned_enemies:
		if enemy_stack[0] == Units.Type.TROLL:
			queue_contextual_tutorial(_make_flag_sequence_id(Player.TutorialFlag.TROLL), [TROLL_WARNING_TUTORIAL], null, Player.TutorialFlag.TROLL)
			return

func _on_building_phase_started(_wave_number: int) -> void:
	_maybe_queue_shop_intro()

func _on_tower_created(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	if Towers.is_tower_rite(tower.type):
		queue_contextual_tutorial(_make_flag_sequence_id(Player.TutorialFlag.RITE), [RITE_TUTORIAL], tower, Player.TutorialFlag.RITE)
		return
	if tower.type != Towers.Type.RUINS:
		return
	queue_contextual_tutorial(_make_flag_sequence_id(Player.TutorialFlag.RUINS), [RUINS_TUTORIAL], null, Player.TutorialFlag.RUINS)

func _maybe_queue_shop_intro() -> void: ##queues the day-2 trader explanation once the wave-1 intro is out of the way and the player reaches their second building day
	if Run.player.completed_tutorials[Player.TutorialFlag.SHOP]:
		return
	if not Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		return
	if Run.phases.current_phase != Run.phases.GamePhase.BUILDING:
		return
	if Run.phases.current_wave_number != 2:
		return
	queue_contextual_tutorial(SHOP_SEQUENCE_ID, _build_shop_intro_steps(), null, Player.TutorialFlag.SHOP)

func _build_shop_intro_steps() -> Array[TutorialStep]: ##opens with a real trader-open requirement, then explains the panel once it is visible on screen
	var trader_is_open: bool = Run.player.trader_service.is_menu_open()

	var open_step := TutorialStep.new()
	open_step.instruction_text = "Open the trade menu."
	open_step.panel_anchor = TutorialStep.Anchor.TRADE_ANCHOR
	open_step.highlight_target = TutorialStep.Reference.TRADE_BUTTON
	open_step.trigger_type = TutorialStep.TriggerType.BEGIN_TRIGGERED if trader_is_open else TutorialStep.TriggerType.WAIT_FOR_SIGNAL
	open_step.trigger_signal = UI.trader_open
	open_step.require_confirmation = false
	open_step.override_start_wave_lock = true
	open_step.start_wave_locked = true

	var info_step := TutorialStep.new()
	info_step.instruction_text = "Buy relics and learn rites here. Learned rites stay available in your tower bar. The trader automatically restocks after 2 days, though you may restock it manually.\n[Q to continue.]"
	info_step.panel_anchor = TutorialStep.Anchor.CENTRAL_ANCHOR
	info_step.highlight_target = TutorialStep.Reference.TRADE_MENU
	info_step.trigger_type = TutorialStep.TriggerType.BEGIN_TRIGGERED
	info_step.require_confirmation = true
	info_step.override_start_wave_lock = true
	info_step.start_wave_locked = true

	return [open_step, info_step]

func _has_sequence_id(sequence_id: StringName) -> bool:
	if is_instance_valid(_active_request) and _active_request.sequence_id == sequence_id:
		return true
	for request: TutorialRequest in _pending_requests:
		if request.sequence_id == sequence_id:
			return true
	return false

func _make_flag_sequence_id(flag: Player.TutorialFlag) -> StringName:
	return StringName("flag_%d" % flag)
