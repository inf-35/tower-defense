extends CanvasLayer
class_name TutorialManager

signal start_wave_lock_changed(locked: bool)
signal sequence_finished(sequence_id: StringName)
signal fact_observed(fact: int)
signal intro_continue_requested()

@export var overlay_color_rect: ColorRect
@export var instruction_panel: TutorialPanel
@export var central_anchor: Control
@export var tower_bar_anchor: Control
@export var player_stats_anchor: Control
@export var timeline_anchor: Control
@export var start_wave_anchor: Control
@export var time_controls_anchor: Control
@export var trade_anchor: Control

var _registered_ui_elements: Dictionary[int, Control] = {}
var _active_sequence: Array[TutorialStep] = []
var _current_step_index: int = -1
var _current_sequence_id: StringName = StringName()
var _sequence_world_target: Tower
var _waiting_for_confirmation: bool = false
var _current_signal: Signal = Signal()
var _current_signal_connected: bool = false
var _current_step_target: Control
var _world_hint_previous_speed: float = Clock.BASE_SPEED
var _anchor_node: Control
var _start_wave_locked: bool = false
var _legacy_world_hint_open: bool = false

var _active_intro: bool = false
var _intro_chapter: TutorialContent.Chapter
var _intro_completed_facts: Dictionary[int, bool] = {}
var _intro_hover_targets: Dictionary[int, int] = {}
var _intro_highlight_targets: Array[Control] = []

var _shader_mat: ShaderMaterial

func _ready() -> void:
	_shader_mat = overlay_color_rect.material as ShaderMaterial
	overlay_color_rect.visible = false
	if instruction_panel.get_parent() != self:
		instruction_panel.reparent(self)
	move_child(instruction_panel, get_child_count() - 1)
	instruction_panel.z_as_relative = false
	instruction_panel.z_index = 1
	instruction_panel.clear_content()
	_shader_mat.set_shader_parameter(&"is_active", false)
	_shader_mat.set_shader_parameter(&"spotlight_size_2", Vector2.ZERO)
	overlay_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.tutorial_manager = self

func _process(_delta: float) -> void:
	if _active_intro:
		_update_anchor_position()
		_update_intro_highlight()
		_monitor_intro_hover_targets()
		return

	if not has_active_sequence():
		return

	_update_anchor_position()
	_update_legacy_highlight()
	_monitor_legacy_hover()

func _input(event: InputEvent) -> void:
	if _active_intro and event.is_action_pressed("interact"):
		intro_continue_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not _waiting_for_confirmation:
		return
	if not event.is_action_pressed("interact"):
		return
	_advance_sequence()

func register_element(id: int, node: Control) -> void: ##registers reusable hover/highlight targets without coupling callers to legacy tutorial resources
	_registered_ui_elements[id] = node

func set_start_wave_locked(locked: bool) -> void:
	if _start_wave_locked == locked:
		return
	_start_wave_locked = locked
	start_wave_lock_changed.emit(locked)

func present_intro_chapter(chapter: TutorialContent.Chapter, completed_facts: Dictionary[int, bool]) -> void: ##renders one scripted onboarding chapter and starts observing only its relevant hover targets
	_end_sequence_internal(false)
	_active_intro = true
	_intro_chapter = chapter
	_intro_completed_facts = completed_facts.duplicate()
	_intro_highlight_targets = _resolve_intro_highlight_targets(chapter)
	overlay_color_rect.visible = not _intro_highlight_targets.is_empty()
	_shader_mat.set_shader_parameter(&"is_active", overlay_color_rect.visible)
	instruction_panel.show_intro_chapter(chapter, completed_facts)
	instruction_panel.visible = true
	_anchor_node = _resolve_anchor(chapter.anchor)
	_update_anchor_position()

func set_intro_hover_targets(hover_targets: Dictionary[int, int]) -> void:
	_intro_hover_targets = hover_targets.duplicate()

func set_intro_fact_completed(fact: int) -> void:
	if not _active_intro:
		return
	if _intro_completed_facts.get(int(fact), false):
		return
	_intro_completed_facts[int(fact)] = true
	instruction_panel.set_fact_completed(int(fact))

func clear_intro() -> void:
	_active_intro = false
	_intro_chapter = null
	_intro_completed_facts.clear()
	_intro_hover_targets.clear()
	_intro_highlight_targets.clear()
	_anchor_node = null
	overlay_color_rect.visible = false
	_shader_mat.set_shader_parameter(&"is_active", false)
	_shader_mat.set_shader_parameter(&"spotlight_size_2", Vector2.ZERO)
	instruction_panel.clear_content()

func has_active_sequence() -> bool:
	return _current_step_index != -1

func get_active_sequence_id() -> StringName:
	return _current_sequence_id

func start_sequence(steps: Array[TutorialStep], sequence_id: StringName = StringName()) -> void: ##starts a legacy one-shot tutorial sequence after the intro has yielded control
	if has_active_sequence():
		_end_sequence_internal(false)
	clear_intro()
	_sequence_world_target = null
	_active_sequence = steps
	_current_sequence_id = sequence_id
	_current_step_index = -1
	instruction_panel.visible = true
	_advance_sequence()

func start_world_sequence(steps: Array[TutorialStep], sequence_id: StringName, tower: Tower) -> void: ##anchors a legacy one-shot beside a runtime world target such as destroyed towers
	if has_active_sequence():
		_end_sequence_internal(false)
	clear_intro()
	_sequence_world_target = tower
	_active_sequence = steps
	_current_sequence_id = sequence_id
	_current_step_index = -1
	instruction_panel.visible = true
	_advance_sequence()

func end_tutorial() -> void:
	_end_sequence_internal(true)

func _advance_sequence() -> void:
	_waiting_for_confirmation = false
	_disconnect_current_signal()
	_current_step_index += 1
	if _current_step_index >= _active_sequence.size():
		_end_sequence_internal(true)
		return

	var step: TutorialStep = _active_sequence[_current_step_index]
	_apply_step_pause(step)
	_current_step_target = _resolve_legacy_target(step)
	_anchor_node = _resolve_legacy_anchor(step)

	var should_highlight: bool = _current_step_target != null and step.highlight
	overlay_color_rect.visible = should_highlight
	_shader_mat.set_shader_parameter(&"is_active", should_highlight)

	var initial_text: String = step.instruction_text if not step.instruction_text.is_empty() else step.success_text
	instruction_panel.show_legacy_message(KeywordService.style_tutorial_text(initial_text))
	_update_anchor_position()

	match step.trigger_type:
		TutorialStep.TriggerType.BEGIN_TRIGGERED:
			_complete_sequence_step()
		TutorialStep.TriggerType.WAIT_FOR_SIGNAL:
			_current_signal = step.trigger_signal
			if step.trigger_signal:
				step.trigger_signal.connect(_on_trigger_signal)
				_current_signal_connected = true
		TutorialStep.TriggerType.HOVER_ELEMENT:
			pass
		TutorialStep.TriggerType.PRESS_ACTION:
			pass
		_:
			push_error("TutorialManager: unsupported legacy trigger type %s" % step.trigger_type)
			_complete_sequence_step()

func _complete_sequence_step() -> void:
	var step: TutorialStep = _active_sequence[_current_step_index]
	_disconnect_current_signal()
	if step.require_confirmation:
		_waiting_for_confirmation = true
		if not step.success_text.is_empty():
			instruction_panel.show_legacy_message(KeywordService.style_tutorial_text(step.success_text))
		return
	_advance_sequence()

func _monitor_legacy_hover() -> void:
	if _current_step_index < 0 or _current_step_index >= _active_sequence.size():
		return
	var step: TutorialStep = _active_sequence[_current_step_index]
	if step.trigger_type != TutorialStep.TriggerType.HOVER_ELEMENT:
		return
	if not is_instance_valid(_current_step_target) or not _current_step_target.visible:
		return
	if _current_step_target.get_global_rect().has_point(get_viewport().get_mouse_position()):
		_complete_sequence_step()

func _update_legacy_highlight() -> void:
	if not overlay_color_rect.visible or not is_instance_valid(_current_step_target):
		return
	_update_spotlight_position(_current_step_target)

func _update_intro_highlight() -> void:
	if not overlay_color_rect.visible or _intro_highlight_targets.is_empty():
		return
	var visible_targets: Array[Control] = []
	for target: Control in _intro_highlight_targets:
		if is_instance_valid(target) and target.visible:
			visible_targets.append(target)
	if visible_targets.is_empty():
		_shader_mat.set_shader_parameter(&"spotlight_size_2", Vector2.ZERO)
		return
	if visible_targets.size() == 1:
		_update_spotlight_position(visible_targets[0])
		return
	_update_spotlight_pair(visible_targets[0], visible_targets[1])

func _monitor_intro_hover_targets() -> void:
	for fact: int in _intro_hover_targets:
		if _intro_completed_facts.get(fact, false):
			continue
		var element: Control = _registered_ui_elements.get(_intro_hover_targets[fact])
		if not is_instance_valid(element) or not element.visible:
			continue
		if element.get_global_rect().has_point(get_viewport().get_mouse_position()):
			fact_observed.emit(fact)

func _on_trigger_signal(...args) -> void:
	if _current_step_index < 0 or _current_step_index >= _active_sequence.size():
		return
	var desired_parameters: Array = _active_sequence[_current_step_index].desired_parameters
	for i: int in range(desired_parameters.size()):
		if i >= args.size() or desired_parameters[i] != args[i]:
			return
	_complete_sequence_step()

func _disconnect_current_signal() -> void:
	if _current_signal_connected and _current_signal.is_connected(_on_trigger_signal):
		_current_signal.disconnect(_on_trigger_signal)
	_current_signal = Signal()
	_current_signal_connected = false

func _apply_step_pause(step: TutorialStep) -> void:
	if step.pause_clock and not _legacy_world_hint_open:
		_legacy_world_hint_open = true
		_world_hint_previous_speed = Clock.speed_multiplier
		Clock.speed_multiplier = Clock.PAUSE_SPEED
	elif not step.pause_clock and _legacy_world_hint_open:
		_legacy_world_hint_open = false
		Clock.speed_multiplier = _world_hint_previous_speed

func _resolve_legacy_target(step: TutorialStep) -> Control:
	match step.highlight_target:
		TutorialStep.Reference.PLAYER_STATS:
			return _registered_ui_elements.get(int(TutorialContent.Element.PLAYER_STATS))
		TutorialStep.Reference.WAVE_TIMELINE:
			return _registered_ui_elements.get(int(TutorialContent.Element.WAVE_TIMELINE))
		TutorialStep.Reference.START_WAVE_BUTTON:
			return _registered_ui_elements.get(int(TutorialContent.Element.START_WAVE_BUTTON))
		TutorialStep.Reference.TRADE_BUTTON:
			return _registered_ui_elements.get(int(TutorialContent.Element.TRADE_BUTTON))
		TutorialStep.Reference.TRADE_MENU:
			return _registered_ui_elements.get(int(TutorialContent.Element.TRADE_MENU))
	return null

func _resolve_anchor(anchor: TutorialContent.Anchor) -> Control:
	match anchor:
		TutorialContent.Anchor.CENTRAL:
			return central_anchor
		TutorialContent.Anchor.TOWER_BAR:
			return tower_bar_anchor
		TutorialContent.Anchor.PLAYER_STATS:
			return player_stats_anchor
		TutorialContent.Anchor.TIMELINE:
			return timeline_anchor
		TutorialContent.Anchor.START_WAVE:
			return start_wave_anchor
		TutorialContent.Anchor.TIME_CONTROLS:
			return time_controls_anchor
	return null

func _resolve_legacy_anchor(step: TutorialStep) -> Control:
	match step.panel_anchor:
		TutorialStep.Anchor.CENTRAL_ANCHOR:
			return central_anchor
		TutorialStep.Anchor.TOWER_BAR_ANCHOR:
			return tower_bar_anchor
		TutorialStep.Anchor.PLAYER_STATS_ANCHOR:
			return player_stats_anchor
		TutorialStep.Anchor.TIMELINE_ANCHOR:
			return timeline_anchor
		TutorialStep.Anchor.START_WAVE_ANCHOR:
			return start_wave_anchor
		TutorialStep.Anchor.TARGET_OFFSET:
			return central_anchor
		TutorialStep.Anchor.TIME_CONTROLS_ANCHOR:
			return time_controls_anchor
		TutorialStep.Anchor.TRADE_ANCHOR:
			return trade_anchor
	return null

func _update_anchor_position() -> void:
	if _has_active_world_target():
		_update_world_hint_panel()
		return
	if not is_instance_valid(_anchor_node):
		return
	var anchor_rect: Rect2 = _anchor_node.get_global_rect()
	instruction_panel.position = anchor_rect.position
	instruction_panel.size = anchor_rect.size

func _has_active_world_target() -> bool:
	return has_active_sequence() and is_instance_valid(_sequence_world_target) and _active_sequence[_current_step_index].panel_anchor == TutorialStep.Anchor.TARGET_OFFSET

func _update_world_hint_panel() -> void:
	if not is_instance_valid(_sequence_world_target):
		return
	var step: TutorialStep = _active_sequence[_current_step_index]
	var screen_pos: Vector2 = _sequence_world_target.get_global_transform_with_canvas().origin
	screen_pos.x += float(_sequence_world_target.size.x) * Island.CELL_SIZE * 0.35
	screen_pos.y -= float(_sequence_world_target.size.y) * Island.CELL_SIZE * 0.45

	instruction_panel.reset_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_pos: Vector2 = screen_pos + step.target_offset
	panel_pos.x = clampf(panel_pos.x, 12.0, viewport_size.x - instruction_panel.size.x - 12.0)
	panel_pos.y = clampf(panel_pos.y, 12.0, viewport_size.y - instruction_panel.size.y - 12.0)
	instruction_panel.position = panel_pos

func _update_spotlight_position(node: Control) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = node.get_global_rect()
	_shader_mat.set_shader_parameter(&"spotlight_center", rect.get_center() / viewport_size)
	_shader_mat.set_shader_parameter(&"spotlight_size", rect.size / viewport_size)
	_shader_mat.set_shader_parameter(&"spotlight_size_2", Vector2.ZERO)

func _update_spotlight_pair(primary: Control, secondary: Control) -> void:
	if not is_instance_valid(primary) or not primary.visible:
		if is_instance_valid(secondary) and secondary.visible:
			_update_spotlight_position(secondary)
		return
	if not is_instance_valid(secondary) or not secondary.visible:
		_update_spotlight_position(primary)
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var primary_rect: Rect2 = primary.get_global_rect()
	var secondary_rect: Rect2 = secondary.get_global_rect()
	_shader_mat.set_shader_parameter(&"spotlight_center", primary_rect.get_center() / viewport_size)
	_shader_mat.set_shader_parameter(&"spotlight_size", primary_rect.size / viewport_size)
	_shader_mat.set_shader_parameter(&"spotlight_center_2", secondary_rect.get_center() / viewport_size)
	_shader_mat.set_shader_parameter(&"spotlight_size_2", secondary_rect.size / viewport_size)

func _resolve_intro_highlight_targets(chapter: TutorialContent.Chapter) -> Array[Control]:
	var element_ids: Array[int] = chapter.highlight_elements
	if element_ids.is_empty() and chapter.highlight_element != TutorialContent.Element.NONE:
		element_ids = [chapter.highlight_element]

	var targets: Array[Control] = []
	for element_id: int in element_ids:
		var target: Control = _registered_ui_elements.get(element_id)
		if is_instance_valid(target):
			targets.append(target)
	return targets

func _end_sequence_internal(emit_finished: bool) -> void:
	var finished_sequence_id: StringName = _current_sequence_id
	_disconnect_current_signal()
	if _legacy_world_hint_open:
		_legacy_world_hint_open = false
		Clock.speed_multiplier = _world_hint_previous_speed
	_active_sequence.clear()
	_current_step_index = -1
	_current_sequence_id = StringName()
	_sequence_world_target = null
	_current_step_target = null
	_anchor_node = null
	_waiting_for_confirmation = false
	overlay_color_rect.visible = false
	_shader_mat.set_shader_parameter(&"is_active", false)
	instruction_panel.clear_content()
	if emit_finished and finished_sequence_id != StringName():
		sequence_finished.emit(finished_sequence_id)
