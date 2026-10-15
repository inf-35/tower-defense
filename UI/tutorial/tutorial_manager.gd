extends CanvasLayer
class_name TutorialManager


signal start_wave_lock_changed(locked: bool)
signal fact_observed(fact: int)
signal continue_requested()

@export var instruction_panel: TutorialPanel
@export var central_anchor: Control
@export var tower_bar_anchor: Control
@export var player_stats_anchor: Control
@export var timeline_anchor: Control
@export var start_wave_anchor: Control
@export var trade_anchor: Control

@export_group("Chapter Pointer Objects")
##scene pointers shown only during the camera-controls chapter
@export var camera_controls_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the tower-placement chapter
@export var towers_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the information-hover chapter
@export var information_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the start-wave chapter
@export var start_wave_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the destroyed-tower hint
@export var destroyed_tower_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the first troll warning
@export var troll_warning_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the first rite explanation
@export var rite_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the first ruins explanation
@export var ruins_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only while asking the player to open the trader
@export var shop_open_pointer_objects: Array[CanvasItem] = []
##scene pointers shown only during the trader explanation
@export var shop_info_pointer_objects: Array[CanvasItem] = []

@export_group("Chapter Pointer Motion")
##smallest multiplier in the pointer's forceful breathing pulse
@export_range(0.0, 4.0, 0.05) var pointer_scale_multiplier_min: float = 1.5
##largest multiplier in the pointer's forceful breathing pulse
@export_range(0.0, 4.0, 0.05) var pointer_scale_multiplier_max: float = 2.0
##gentle angular displacement layered over the stronger scale pulse
@export_range(0.0, 30.0, 0.5, "degrees") var pointer_rotation_degrees: float = 5.0
##time for one complete expand-contract and left-right cycle
@export_range(0.1, 4.0, 0.05, "suffix:s") var pointer_oscillation_duration: float = 0.65

var _registered_ui_elements: Dictionary[int, Control] = {}
var _chapter_pointer_objects: Dictionary[StringName, Array] = {}
var _pointer_base_scales: Dictionary[CanvasItem, Vector2] = {}
var _pointer_base_rotations: Dictionary[CanvasItem, float] = {}
var _pointer_motion_tweens: Dictionary[CanvasItem, Tween] = {}
var _active_chapter: TutorialContent.Chapter
var _completed_facts: Dictionary[int, bool] = {}
var _world_target: Tower
var _anchor_node: Control
var _highlighted_controls: Dictionary[Control, Color] = {}
var _start_wave_locked: bool = false
var _chapter_pause_active: bool = false
var _pre_chapter_speed: float = Clock.BASE_SPEED

func _ready() -> void: ##binds the shared panel and exposes this presenter through the ui bus
	set_process(false)
	_chapter_pointer_objects = {
		&"camera_controls": camera_controls_pointer_objects,
		&"towers": towers_pointer_objects,
		&"information": information_pointer_objects,
		&"start_wave": start_wave_pointer_objects,
		&"destroyed_tower": destroyed_tower_pointer_objects,
		&"troll_warning": troll_warning_pointer_objects,
		&"rite": rite_pointer_objects,
		&"ruins": ruins_pointer_objects,
		&"shop_open": shop_open_pointer_objects,
		&"shop_info": shop_info_pointer_objects,
	}
	_hide_all_chapter_pointer_objects()
	if instruction_panel.get_parent() != self:
		instruction_panel.reparent(self)
	move_child(instruction_panel, get_child_count() - 1)
	instruction_panel.z_as_relative = false
	instruction_panel.z_index = 1
	instruction_panel.clear_content()
	UI.tutorial_manager = self

func _process(_delta: float) -> void: ##tracks the active panel anchor and observes any chapter-authored hover facts
	if not is_instance_valid(_active_chapter):
		return
	_update_anchor_position()
	_monitor_hover_targets()

func _input(event: InputEvent) -> void: ##forwards the shared tutorial continuation action while a chapter is visible
	if not is_instance_valid(_active_chapter) or not event.is_action_pressed("interact"):
		return
	continue_requested.emit()
	get_viewport().set_input_as_handled()

func register_element(id: int, node: Control) -> void: ##registers reusable targets and refreshes highlights that were waiting for this control
	_registered_ui_elements[id] = node
	if is_instance_valid(_active_chapter):
		_refresh_active_highlights()

func set_start_wave_locked(locked: bool) -> void: ##publishes start-wave availability only when its tutorial-owned state changes
	if _start_wave_locked == locked:
		return
	_start_wave_locked = locked
	start_wave_lock_changed.emit(locked)

func present_chapter(chapter: TutorialContent.Chapter, completed_facts: Dictionary[int, bool], world_target: Tower = null) -> void: ##presents one chapter through the shared highlight, pause, anchor, and fact-observation lifecycle
	clear_chapter()
	_active_chapter = chapter
	_completed_facts = completed_facts.duplicate()
	_world_target = world_target
	_anchor_node = _resolve_anchor(chapter.anchor)
	_apply_chapter_pause(chapter.pause_clock)
	_refresh_active_highlights()
	_set_active_chapter_pointer_objects(chapter.id)
	instruction_panel.show_chapter(chapter, completed_facts)
	instruction_panel.visible = true
	set_process(true)
	_update_anchor_position()

func set_fact_completed(fact: int) -> void: ##updates the active chapter once a fact becomes true
	if not is_instance_valid(_active_chapter):
		return
	if _completed_facts.get(fact, false):
		return
	_completed_facts[fact] = true
	instruction_panel.set_fact_completed(fact)

func clear_chapter() -> void: ##clears presentation state and restores transient highlight and clock changes
	set_process(false)
	_hide_all_chapter_pointer_objects()
	_clear_highlights()
	_restore_chapter_pause()
	_active_chapter = null
	_completed_facts.clear()
	_world_target = null
	_anchor_node = null
	instruction_panel.clear_content()

func _monitor_hover_targets() -> void: ##emits incomplete chapter facts when the pointer enters their registered controls
	for fact: int in _active_chapter.hover_targets:
		if _completed_facts.get(fact, false):
			continue
		var element: Control = _registered_ui_elements.get(_active_chapter.hover_targets[fact])
		if not is_instance_valid(element) or not element.visible:
			continue
		if element.get_global_rect().has_point(get_viewport().get_mouse_position()):
			fact_observed.emit(fact)

func _resolve_anchor(anchor: TutorialContent.Anchor) -> Control: ##maps chapter anchor ids onto the scene-authored tutorial layout controls
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
		TutorialContent.Anchor.TRADE:
			return trade_anchor
		TutorialContent.Anchor.TARGET_OFFSET:
			return central_anchor
	return central_anchor

func _update_anchor_position() -> void: ##keeps screen and world anchored tutorial panels aligned as their targets move
	if _active_chapter.anchor == TutorialContent.Anchor.TARGET_OFFSET and is_instance_valid(_world_target):
		_update_world_target_position()
		return
	if not is_instance_valid(_anchor_node):
		return
	var anchor_rect: Rect2 = _anchor_node.get_global_rect()
	instruction_panel.position = anchor_rect.position
	instruction_panel.size = anchor_rect.size

func _update_world_target_position() -> void: ##positions a contextual chapter beside its world tower while keeping the panel on screen
	var screen_pos: Vector2 = _world_target.get_global_transform_with_canvas().origin
	screen_pos.x += float(_world_target.size.x) * Island.CELL_SIZE * 0.35
	screen_pos.y -= float(_world_target.size.y) * Island.CELL_SIZE * 0.45

	instruction_panel.reset_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_pos: Vector2 = screen_pos + _active_chapter.target_offset
	panel_pos.x = clampf(panel_pos.x, 12.0, viewport_size.x - instruction_panel.size.x - 12.0)
	panel_pos.y = clampf(panel_pos.y, 12.0, viewport_size.y - instruction_panel.size.y - 12.0)
	instruction_panel.position = panel_pos

func _resolve_highlight_targets() -> Array[Control]: ##resolves the active chapter's authored element ids to live ui controls
	var element_ids: Array[int] = _active_chapter.highlight_elements
	var targets: Array[Control] = []
	for element_id: int in element_ids:
		var target: Control = _registered_ui_elements.get(element_id)
		if is_instance_valid(target):
			targets.append(target)
	return targets

func _refresh_active_highlights() -> void: ##reapplies highlights after chapter changes or late ui registration
	_set_highlight_targets(_resolve_highlight_targets())

func _set_highlight_targets(targets: Array[Control]) -> void: ##brightens controls while preserving their exact prior modulate for restoration
	_clear_highlights()
	var highlight_multiplier: Color = Color(1.0,1.0,1.0,1.0)
	for target: Control in targets:
		if not is_instance_valid(target) or _highlighted_controls.has(target):
			continue
		_highlighted_controls[target] = target.modulate
		target.modulate *= highlight_multiplier

func _clear_highlights() -> void: ##restores controls changed by the current chapter without assuming they still exist
	for target: Control in _highlighted_controls:
		if is_instance_valid(target):
			target.modulate = _highlighted_controls[target]
	_highlighted_controls.clear()

func _set_active_chapter_pointer_objects(chapter_id: StringName) -> void: ##shows only the scene-authored cursor and pointer objects bound to the active chapter
	_hide_all_chapter_pointer_objects()
	var pointer_objects: Array = _chapter_pointer_objects.get(chapter_id, [])
	for pointer_object: CanvasItem in pointer_objects:
		if not is_instance_valid(pointer_object):
			continue
		_capture_pointer_transform(pointer_object)
		pointer_object.visible = true
		_start_pointer_motion(pointer_object)

func _hide_all_chapter_pointer_objects() -> void: ##keeps tutorial pointers dormant outside their explicitly bound chapter
	for pointer_objects: Array in _chapter_pointer_objects.values():
		for pointer_object: CanvasItem in pointer_objects:
			if not is_instance_valid(pointer_object):
				continue
			_stop_pointer_motion(pointer_object)
			pointer_object.visible = false

func _capture_pointer_transform(pointer_object: CanvasItem) -> void: ##stores authored transforms once so chapter animation never accumulates scale or rotation
	if _pointer_base_scales.has(pointer_object):
		return
	var authored_scale: Vector2 = pointer_object.get(&"scale")
	_pointer_base_scales[pointer_object] = authored_scale
	_pointer_base_rotations[pointer_object] = float(pointer_object.get(&"rotation"))

func _start_pointer_motion(pointer_object: CanvasItem) -> void: ##runs one fast sinusoidal scale pulse and mild rotational sway for an active pointer
	_stop_pointer_motion(pointer_object)
	_capture_pointer_transform(pointer_object)
	_apply_pointer_motion(0.0, pointer_object)
	var motion_tween: Tween = create_tween().set_loops()
	motion_tween.tween_method(
		_apply_pointer_motion.bind(pointer_object),
		0.0,
		TAU,
		maxf(pointer_oscillation_duration, 0.1)
	)
	_pointer_motion_tweens[pointer_object] = motion_tween

func _apply_pointer_motion(phase: float, pointer_object: CanvasItem) -> void: ##maps tween phase onto the configured pulse while retaining each pointer's authored proportions
	if not is_instance_valid(pointer_object):
		return
	var pulse_weight: float = 0.5 - 0.5 * cos(phase)
	var minimum_scale: float = minf(pointer_scale_multiplier_min, pointer_scale_multiplier_max)
	var maximum_scale: float = maxf(pointer_scale_multiplier_min, pointer_scale_multiplier_max)
	var scale_multiplier: float = lerpf(minimum_scale, maximum_scale, pulse_weight)
	pointer_object.set(&"scale", _pointer_base_scales.get(pointer_object, Vector2.ONE) * scale_multiplier)
	pointer_object.set(&"rotation", _pointer_base_rotations.get(pointer_object, 0.0) + sin(phase) * deg_to_rad(pointer_rotation_degrees))

func _stop_pointer_motion(pointer_object: CanvasItem) -> void: ##kills active motion and returns the pointer to its exact authored transform
	var motion_tween: Tween = _pointer_motion_tweens.get(pointer_object, null)
	if is_instance_valid(motion_tween):
		motion_tween.kill()
	_pointer_motion_tweens.erase(pointer_object)
	if _pointer_base_scales.has(pointer_object):
		pointer_object.set(&"scale", _pointer_base_scales[pointer_object])
		pointer_object.set(&"rotation", _pointer_base_rotations[pointer_object])

func _apply_chapter_pause(should_pause: bool) -> void: ##captures the current game speed before a chapter temporarily pauses the clock
	if not should_pause or _chapter_pause_active:
		return
	_chapter_pause_active = true
	_pre_chapter_speed = Clock.speed_multiplier
	Clock.speed_multiplier = Clock.PAUSE_SPEED

func _restore_chapter_pause() -> void: ##restores the speed active before the paused chapter opened
	if not _chapter_pause_active:
		return
	_chapter_pause_active = false
	Clock.speed_multiplier = _pre_chapter_speed
