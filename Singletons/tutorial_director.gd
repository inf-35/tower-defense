extends Node
class_name TutorialDirector

class TutorialRequest extends RefCounted:
	var sequence_id: StringName = StringName()
	var chapters: Array[TutorialContent.Chapter] = []
	var world_target: Tower
	var completion_flag: int = -1
	var chapter_index: int = 0
	var completed_facts: Dictionary[int, bool] = {}

const SHOP_SEQUENCE_ID: StringName = &"shop_intro"

var _pending_requests: Array[TutorialRequest] = []
var _active_request: TutorialRequest
var _intro_chapters: Array[TutorialContent.Chapter] = []
var _completed_intro_facts: Dictionary[int, bool] = {}
var _intro_active: bool = false
var _active_chapter_index: int = -1
var _intro_advance_generation: int = 0
var _request_advance_generation: int = 0
var _restored_intro_state: Dictionary = {}

func refresh_runtime_connections() -> void: ##binds the presenter and run-scoped event sources used to complete tutorial facts
	if not is_instance_valid(UI.tutorial_manager):
		return
	if not UI.tutorial_manager.fact_observed.is_connected(_on_fact_observed):
		UI.tutorial_manager.fact_observed.connect(_on_fact_observed)
	if not UI.tutorial_manager.continue_requested.is_connected(_on_continue_requested):
		UI.tutorial_manager.continue_requested.connect(_on_continue_requested)
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
	if not UI.trader_open.is_connected(_on_trader_opened):
		UI.trader_open.connect(_on_trader_opened)
	if is_instance_valid(Run.references.camera):
		var camera: Camera = Run.references.camera
		if not camera.tutorial_pan_observed.is_connected(_on_camera_panned):
			camera.tutorial_pan_observed.connect(_on_camera_panned)
		if not camera.tutorial_zoom_observed.is_connected(_on_camera_zoomed):
			camera.tutorial_zoom_observed.connect(_on_camera_zoomed)
	if is_instance_valid(Run.references.island) and not Run.references.island.tower_created.is_connected(_on_tower_created):
		Run.references.island.tower_created.connect(_on_tower_created)

func begin_new_game() -> void: ##starts onboarding for fresh profiles and leaves later contextual requests queued behind it
	_pending_requests.clear()
	_active_request = null
	_completed_intro_facts.clear()
	_intro_active = false
	_active_chapter_index = -1
	_intro_advance_generation = 0
	_request_advance_generation = 0
	_build_intro_chapters()
	refresh_runtime_connections()
	if is_instance_valid(UI.tutorial_manager):
		UI.tutorial_manager.clear_chapter()
		UI.tutorial_manager.set_start_wave_locked(false)
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		return
	_begin_intro_if_needed()

func _begin_intro_if_needed() -> void: ##opens or restores the current onboarding chapter when onboarding is incomplete
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING] or _intro_active:
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
	_show_active_intro_chapter()

func _notify_intro_fact(fact: int) -> void: ##records one sticky onboarding fact and schedules advancement when its active chapter is complete
	if not _intro_active:
		return
	if _completed_intro_facts.get(fact, false):
		return
	_completed_intro_facts[fact] = true
	UI.tutorial_manager.set_fact_completed(fact)
	if _is_active_intro_chapter_complete():
		_schedule_intro_advance()

func _queue_contextual_tutorial(sequence_id: StringName, chapters: Array[TutorialContent.Chapter], world_target: Tower = null, completion_flag: int = -1) -> void: ##queues chapter-authored contextual content behind onboarding and the current request
	if chapters.is_empty():
		return
	if completion_flag >= 0 and Run.player.completed_tutorials[completion_flag]:
		return
	if _has_sequence_id(sequence_id):
		return
	var request := TutorialRequest.new()
	request.sequence_id = sequence_id
	request.chapters = chapters
	request.world_target = world_target
	request.completion_flag = completion_flag
	_pending_requests.append(request)
	if not _intro_active and not is_instance_valid(_active_request):
		_start_next_pending_request()

func request_destroyed_tower_tutorial(tower: Tower) -> void: ##queues the first destroyed-tower explanation beside the affected tower
	if not is_instance_valid(tower):
		return
	_queue_contextual_tutorial(
		_make_flag_sequence_id(Player.TutorialFlag.TOWER_DESTROYED),
		_build_destroyed_tower_chapters(),
		tower,
		Player.TutorialFlag.TOWER_DESTROYED
	)

func get_save_data() -> Dictionary: ##serializes resumable onboarding progress while contextual hints remain event-regenerated
	return {
		"intro_active": _intro_active,
		"active_chapter_index": _active_chapter_index,
		"completed_facts": _completed_intro_facts.keys(),
	}

func load_save_data(data: Dictionary) -> void: ##restores onboarding chapter state and reconnects run-scoped fact sources
	_build_intro_chapters()
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

func _restore_after_load() -> void: ##resumes saved onboarding or regenerates the day-two shop hint when appropriate
	if Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		_maybe_queue_shop_intro()
		return
	if bool(_restored_intro_state.get("intro_active", false)):
		_begin_intro_if_needed()
		return
	_maybe_queue_shop_intro()

func _build_intro_chapters() -> void: ##authors the primary onboarding as chapter data
	_intro_chapters.clear()

	var camera_controls := TutorialContent.Chapter.new()
	camera_controls.id = &"camera_controls"
	camera_controls.anchor = TutorialContent.Anchor.CENTRAL
	camera_controls.checklist_items = [
		TutorialContent.ChecklistItem.new(TutorialContent.Fact.CAMERA_PANNED, "Move the camera with WASD or middle mouse drag."),
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
	towers.allow_manual_continue = true
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
	start_wave.highlight_elements = [TutorialContent.Element.START_WAVE_BUTTON]
	start_wave.start_wave_locked = false
	start_wave.auto_advance = false
	_intro_chapters.append(start_wave)

func _show_active_intro_chapter() -> void: ##presents the current onboarding chapter or completes onboarding after the final chapter
	if _active_chapter_index < 0:
		return
	if _active_chapter_index >= _intro_chapters.size():
		_complete_intro()
		return
	var chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
	UI.tutorial_manager.set_start_wave_locked(chapter.start_wave_locked)
	UI.tutorial_manager.present_chapter(chapter, _completed_intro_facts)
	if _is_active_intro_chapter_complete():
		_schedule_intro_advance()

func _is_active_intro_chapter_complete() -> bool: ##checks the active onboarding chapter against sticky onboarding facts
	if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
		return false
	return _are_chapter_facts_complete(_intro_chapters[_active_chapter_index], _completed_intro_facts)

func _schedule_intro_advance() -> void: ##starts the active chapter's authored auto-advance delay
	if not _is_active_intro_chapter_complete():
		return
	var chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
	if not chapter.auto_advance:
		return
	_intro_advance_generation += 1
	var generation: int = _intro_advance_generation
	_advance_intro_after_delay.call_deferred(generation, chapter.auto_advance_delay)

func _advance_intro_after_delay(generation: int, delay: float) -> void: ##advances only if no newer chapter transition superseded this timer
	await get_tree().create_timer(delay, false).timeout
	if generation != _intro_advance_generation or not _intro_active:
		return
	if not _is_active_intro_chapter_complete():
		return
	_active_chapter_index += 1
	_show_active_intro_chapter()

func _complete_intro() -> void: ##marks onboarding complete and yields presentation to queued contextual chapters
	_intro_active = false
	_active_chapter_index = -1
	UI.tutorial_manager.set_start_wave_locked(false)
	UI.tutorial_manager.clear_chapter()
	Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING] = true
	_start_next_pending_request()

func _start_next_pending_request() -> void: ##starts the next contextual chapter request once onboarding and earlier requests release presentation
	if _intro_active or is_instance_valid(_active_request) or _pending_requests.is_empty():
		return
	_active_request = _pending_requests.pop_front()
	if _active_request.sequence_id == SHOP_SEQUENCE_ID and Run.player.trader_service.is_menu_open():
		_active_request.completed_facts[TutorialContent.Fact.TRADE_OPENED] = true
	_show_active_request_chapter()

func _show_active_request_chapter() -> void: ##presents the active contextual chapter or completes its request after the final chapter
	if not is_instance_valid(_active_request):
		return
	if _active_request.chapter_index >= _active_request.chapters.size():
		_complete_active_request()
		return
	var chapter: TutorialContent.Chapter = _active_request.chapters[_active_request.chapter_index]
	UI.tutorial_manager.set_start_wave_locked(chapter.start_wave_locked)
	UI.tutorial_manager.present_chapter(chapter, _active_request.completed_facts, _active_request.world_target)
	if chapter.auto_advance and _is_active_request_chapter_complete():
		_schedule_request_advance()

func _is_active_request_chapter_complete() -> bool: ##checks the current contextual chapter against its request-local facts
	if not is_instance_valid(_active_request):
		return false
	if _active_request.chapter_index < 0 or _active_request.chapter_index >= _active_request.chapters.size():
		return false
	return _are_chapter_facts_complete(
		_active_request.chapters[_active_request.chapter_index],
		_active_request.completed_facts
	)

func _schedule_request_advance() -> void: ##starts the contextual chapter's authored auto-advance delay
	if not _is_active_request_chapter_complete():
		return
	var chapter: TutorialContent.Chapter = _active_request.chapters[_active_request.chapter_index]
	_request_advance_generation += 1
	var generation: int = _request_advance_generation
	_advance_request_after_delay.call_deferred(generation, chapter.auto_advance_delay)

func _advance_request_after_delay(generation: int, delay: float) -> void: ##advances a contextual request only if its active chapter still owns the timer
	await get_tree().create_timer(delay, false).timeout
	if generation != _request_advance_generation or not is_instance_valid(_active_request):
		return
	if not _is_active_request_chapter_complete():
		return
	_active_request.chapter_index += 1
	_show_active_request_chapter()

func _complete_active_request() -> void: ##records one contextual tutorial completion and releases the queue
	if not is_instance_valid(_active_request):
		return
	if _active_request.completion_flag >= 0:
		Run.player.completed_tutorials[_active_request.completion_flag] = true
	_active_request = null
	UI.tutorial_manager.set_start_wave_locked(false)
	UI.tutorial_manager.clear_chapter()
	_start_next_pending_request()

func _are_chapter_facts_complete(chapter: TutorialContent.Chapter, completed_facts: Dictionary[int, bool]) -> bool: ##checks one chapter's requirements against the owning sequence's fact set
	for fact: int in chapter.get_required_facts():
		if not completed_facts.get(fact, false):
			return false
	return true

func _record_contextual_fact(fact: int) -> void: ##records a fact for active and queued requests so delayed chapters do not repeat already completed actions
	if is_instance_valid(_active_request) and not _active_request.completed_facts.get(fact, false):
		_active_request.completed_facts[fact] = true
		UI.tutorial_manager.set_fact_completed(fact)
		if _is_active_request_chapter_complete() and _active_request.chapters[_active_request.chapter_index].auto_advance:
			_schedule_request_advance()
	for request: TutorialRequest in _pending_requests:
		request.completed_facts[fact] = true

func _on_fact_observed(fact: int) -> void: ##routes presenter-observed hover facts to the sequence that currently owns presentation
	if _intro_active:
		_notify_intro_fact(fact)
		return
	_record_contextual_fact(fact)

func _on_continue_requested() -> void: ##advances manual chapters only after their authored facts are complete
	if _intro_active:
		if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
			return
		var intro_chapter: TutorialContent.Chapter = _intro_chapters[_active_chapter_index]
		if not intro_chapter.allow_manual_continue or not _is_active_intro_chapter_complete():
			return
		_intro_advance_generation += 1
		_active_chapter_index += 1
		_show_active_intro_chapter()
		return
	if not is_instance_valid(_active_request):
		return
	if _active_request.chapter_index < 0 or _active_request.chapter_index >= _active_request.chapters.size():
		return
	var request_chapter: TutorialContent.Chapter = _active_request.chapters[_active_request.chapter_index]
	if not request_chapter.allow_manual_continue or not _is_active_request_chapter_complete():
		return
	_request_advance_generation += 1
	_active_request.chapter_index += 1
	_show_active_request_chapter()

func _on_camera_panned() -> void:
	_notify_intro_fact(TutorialContent.Fact.CAMERA_PANNED)

func _on_camera_zoomed() -> void:
	_notify_intro_fact(TutorialContent.Fact.CAMERA_ZOOMED)

func _on_tower_option_selected(_tower_type: Towers.Type) -> void:
	_notify_intro_fact(TutorialContent.Fact.TOWER_BAR_SELECTED)

func _on_tower_placed(tower_type: Towers.Type, tower: Tower) -> void: ##records only live friendly placements relevant to onboarding
	if not is_instance_valid(tower) or tower.hostile or tower.environmental or tower.abstractive:
		return
	if tower_type == Towers.Type.TURRET:
		_notify_intro_fact(TutorialContent.Fact.TURRET_PLACED)
	if tower_type == Towers.Type.FARM:
		_notify_intro_fact(TutorialContent.Fact.FARM_PLACED)

func _on_combat_started(_wave_number: int) -> void: ##completes onboarding when combat begins from its final start-wave chapter
	if not _intro_active:
		return
	if _active_chapter_index < 0 or _active_chapter_index >= _intro_chapters.size():
		return
	if _intro_chapters[_active_chapter_index].id == &"start_wave":
		_complete_intro()

func _on_wave_cycle_started(wave_number: int) -> void: ##queues the troll route warning before the first planned troll wave
	var planned_enemies: Array[Array] = WaveEnemies.get_enemies_for_wave(wave_number)
	for enemy_stack: Array in planned_enemies:
		if enemy_stack[0] != Units.Type.TROLL:
			continue
		_queue_contextual_tutorial(
			_make_flag_sequence_id(Player.TutorialFlag.TROLL),
			_build_troll_warning_chapters(),
			null,
			Player.TutorialFlag.TROLL
		)
		return

func _on_building_phase_started(_wave_number: int) -> void:
	_maybe_queue_shop_intro()

func _on_trader_opened() -> void:
	_record_contextual_fact(TutorialContent.Fact.TRADE_OPENED)

func _on_tower_created(tower: Tower) -> void: ##queues rite and ruins explanations from the first matching live tower creation
	if not is_instance_valid(tower):
		return
	if Towers.is_tower_rite(tower.type):
		_queue_contextual_tutorial(
			_make_flag_sequence_id(Player.TutorialFlag.RITE),
			_build_rite_chapters(),
			tower,
			Player.TutorialFlag.RITE
		)
		return
	if tower.type != Towers.Type.RUINS:
		return
	_queue_contextual_tutorial(
		_make_flag_sequence_id(Player.TutorialFlag.RUINS),
		_build_ruins_chapters(),
		null,
		Player.TutorialFlag.RUINS
	)

func _maybe_queue_shop_intro() -> void: ##queues the day-two trader chapters once onboarding is complete
	if Run.player.completed_tutorials[Player.TutorialFlag.SHOP]:
		return
	if not Run.player.completed_tutorials[Player.TutorialFlag.ONBOARDING]:
		return
	if Run.phases.current_phase != Run.phases.GamePhase.BUILDING:
		return
	if Run.phases.current_wave_number != 2:
		return
	_queue_contextual_tutorial(SHOP_SEQUENCE_ID, _build_shop_chapters(), null, Player.TutorialFlag.SHOP)

func _build_destroyed_tower_chapters() -> Array[TutorialContent.Chapter]: ##authors the paused world hint shown after the first friendly tower is destroyed
	var chapter: TutorialContent.Chapter = _make_manual_message_chapter(
		&"destroyed_tower",
		"Destroyed towers revive next wave.",
		TutorialContent.Anchor.TARGET_OFFSET
	)
	chapter.pause_clock = true
	chapter.target_offset = Vector2(56, -96)
	var chapters: Array[TutorialContent.Chapter] = [chapter]
	return chapters

func _build_troll_warning_chapters() -> Array[TutorialContent.Chapter]: ##authors the first troll route warning beside the wave timeline
	var chapter: TutorialContent.Chapter = _make_manual_message_chapter(
		&"troll_warning",
		"Certain enemies, like {U_TROLL|label=Trolls}, ignore towers and head straight for your keep. Their routes are marked in red.",
		TutorialContent.Anchor.TIMELINE
	)
	var chapters: Array[TutorialContent.Chapter] = [chapter]
	return chapters

func _build_rite_chapters() -> Array[TutorialContent.Chapter]: ##authors the paused first-rite explanation beside its world tower
	var chapter: TutorialContent.Chapter = _make_manual_message_chapter(
		&"rite",
		"{RITE_LABEL|label=Rites} modify nearby towers. [Excavate] an existing rite in the inspector to unlock them permanently.",
		TutorialContent.Anchor.TARGET_OFFSET
	)
	chapter.pause_clock = true
	chapter.target_offset = Vector2(56, -96)
	var chapters: Array[TutorialContent.Chapter] = [chapter]
	return chapters

func _build_ruins_chapters() -> Array[TutorialContent.Chapter]: ##authors the first ruins discovery explanation
	var chapter: TutorialContent.Chapter = _make_manual_message_chapter(
		&"ruins",
		"Ancient {T_RUINS} can be spotted in the uncharted wilds before you expand into them. Once uncovered, [click] one and [search] it to choose a reward."
	)
	var chapters: Array[TutorialContent.Chapter] = [chapter]
	return chapters

func _build_shop_chapters() -> Array[TutorialContent.Chapter]: ##authors the fact-driven trader opening requirement and its follow-up explanation
	var chapters: Array[TutorialContent.Chapter] = []
	if not Run.player.trader_service.is_menu_open():
		var open_chapter := TutorialContent.Chapter.new()
		open_chapter.id = &"shop_open"
		open_chapter.anchor = TutorialContent.Anchor.TRADE
		open_chapter.checklist_items = [
			TutorialContent.ChecklistItem.new(TutorialContent.Fact.TRADE_OPENED, "Open the trade menu."),
		]
		open_chapter.highlight_elements = [TutorialContent.Element.TRADE_BUTTON]
		open_chapter.start_wave_locked = true
		open_chapter.auto_advance_delay = 0.0
		chapters.append(open_chapter)

	var info_chapter: TutorialContent.Chapter = _make_manual_message_chapter(
		&"shop_info",
		"Buy relics and unlock rites here. The trader automatically restocks after 2 days, and you can restock it manually."
	)
	info_chapter.anchor = TutorialContent.Anchor.TRADE
	info_chapter.highlight_elements = [TutorialContent.Element.TRADE_MENU]
	info_chapter.start_wave_locked = true
	chapters.append(info_chapter)
	return chapters

func _make_manual_message_chapter(id: StringName, text: String, anchor: TutorialContent.Anchor = TutorialContent.Anchor.CENTRAL) -> TutorialContent.Chapter: ##builds a one-message chapter with the shared continuation footer
	var chapter := TutorialContent.Chapter.new()
	chapter.id = id
	chapter.anchor = anchor
	chapter.paragraph_text = text
	chapter.footer_text = "[Q to continue.]"
	chapter.start_wave_locked = false
	chapter.auto_advance = false
	chapter.allow_manual_continue = true
	return chapter

func _has_sequence_id(sequence_id: StringName) -> bool: ##deduplicates active and queued contextual requests
	if is_instance_valid(_active_request) and _active_request.sequence_id == sequence_id:
		return true
	for request: TutorialRequest in _pending_requests:
		if request.sequence_id == sequence_id:
			return true
	return false

func _make_flag_sequence_id(flag: Player.TutorialFlag) -> StringName:
	return StringName("flag_%d" % flag)
