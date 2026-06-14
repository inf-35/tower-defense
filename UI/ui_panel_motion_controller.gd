extends Node
class_name UIPanelMotionController

@export var sidebar_panel: Control ##left build bar that should slide offscreen during expansion
@export var stats_panel: Control ##top-left player stats cluster
@export var damage_tracker_panel: Control ##middle-right damage tracker cluster
@export var time_controls_panel: Control ##top-right timeline and speed controls cluster
@export var inspector_panel: Control ##bottom inspector cluster that should hide while nothing is selected
@export var sidebar_margin: float = 48.0 ##extra travel for the sidebar so it fully clears the viewport edge
@export var stats_margin: float = 48.0 ##extra travel for the stats panel so it fully clears the viewport edge
@export var damage_tracker_margin: float = 48.0 ##extra travel for the damage tracker so it fully clears the viewport edge
@export var time_controls_margin: float = 140.0 ##extra travel for time controls because its banner shape needs more clearance
@export var inspector_margin: float = 48.0 ##extra travel for the inspector so it fully clears the viewport edge

var _sidebar_wrapper: PanelMotionWrapper
var _stats_wrapper: PanelMotionWrapper
var _damage_tracker_wrapper: PanelMotionWrapper
var _time_controls_wrapper: PanelMotionWrapper
var _inspector_wrapper: PanelMotionWrapper

var _expansion_active: bool = false
var _inspector_has_target: bool = false

func _ready() -> void: ##wraps the existing large ui panels under stable anchors, then drives their motion from expansion and selection state
	for i in 2: await get_tree().process_frame

	_sidebar_wrapper = _wrap_panel(sidebar_panel, Vector2(-(sidebar_panel.size.x + sidebar_margin), 0.0), &"sidebar")
	_stats_wrapper = _wrap_panel(stats_panel, Vector2(0.0, -(stats_panel.size.y + stats_margin)), &"stats")
	_damage_tracker_wrapper = _wrap_panel(damage_tracker_panel, Vector2(damage_tracker_panel.size.x + damage_tracker_margin, 0.0), &"damage_tracker")
	_time_controls_wrapper = _wrap_panel(time_controls_panel, Vector2(time_controls_panel.size.x + time_controls_margin, 0.0), &"time_controls")
	_inspector_wrapper = _wrap_panel(inspector_panel, Vector2(0.0, inspector_panel.size.y + inspector_margin), &"inspector")

	UI.display_expansion_choices.connect(_on_expansion_started)
	UI.hide_expansion_choices.connect(_on_expansion_ended)
	UI.expansion_finished.connect(_on_expansion_ended)
	UI.update_inspector_bar.connect(_on_inspector_target_changed)

	_apply_panel_states(true)

func _wrap_panel(panel: Control, hidden_offset: Vector2, key: StringName) -> PanelMotionWrapper:
	if not is_instance_valid(panel):
		return null

	var parent_control: Control = panel.get_parent() as Control
	if not is_instance_valid(parent_control):
		return null

	var original_index: int = panel.get_index()

	var anchor: Control = Control.new()
	anchor.name = "%s_anchor" % key
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy_layout(panel, anchor)
	parent_control.add_child(anchor)
	parent_control.move_child(anchor, original_index)

	var wrapper := PanelMotionWrapper.new()
	wrapper.name = "%s_wrapper" % key
	wrapper.anchor_node = anchor
	wrapper.hidden_offset = hidden_offset
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy_layout(panel, wrapper)
	parent_control.add_child(wrapper)
	parent_control.move_child(wrapper, original_index + 1)

	parent_control.remove_child(panel)
	wrapper.add_child(panel)
	_stretch_panel_to_wrapper(panel)
	wrapper.content = panel
	wrapper.snap_shown()

	return wrapper

func _copy_layout(source: Control, target: Control) -> void:
	target.anchor_left = source.anchor_left
	target.anchor_top = source.anchor_top
	target.anchor_right = source.anchor_right
	target.anchor_bottom = source.anchor_bottom
	target.offset_left = source.offset_left
	target.offset_top = source.offset_top
	target.offset_right = source.offset_right
	target.offset_bottom = source.offset_bottom
	target.grow_horizontal = source.grow_horizontal
	target.grow_vertical = source.grow_vertical
	target.custom_minimum_size = source.custom_minimum_size
	target.size_flags_horizontal = source.size_flags_horizontal
	target.size_flags_vertical = source.size_flags_vertical
	target.size_flags_stretch_ratio = source.size_flags_stretch_ratio
	target.layout_direction = source.layout_direction
	target.scale = source.scale

func _stretch_panel_to_wrapper(panel: Control) -> void:
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

func _on_expansion_started(_choices: Array[ExpansionChoice]) -> void:
	_expansion_active = true
	_apply_panel_states()

func _on_expansion_ended() -> void:
	_expansion_active = false
	_apply_panel_states()

func _on_inspector_target_changed(unit: Unit) -> void:
	_inspector_has_target = is_instance_valid(unit)
	_apply_panel_states()

func _apply_panel_states(initial_snap: bool = false) -> void:
	_set_panel_visible(_sidebar_wrapper, not _expansion_active, initial_snap)
	_set_panel_visible(_stats_wrapper, not _expansion_active, initial_snap)
	_set_panel_visible(_damage_tracker_wrapper, not _expansion_active, initial_snap)
	_set_panel_visible(_time_controls_wrapper, not _expansion_active, initial_snap)
	_set_panel_visible(_inspector_wrapper, _inspector_has_target, initial_snap)

func _set_panel_visible(wrapper: PanelMotionWrapper, shown: bool, initial_snap: bool) -> void:
	if not is_instance_valid(wrapper):
		return

	if initial_snap:
		if shown:
			wrapper.snap_shown()
		else:
			wrapper.snap_hidden()
		return

	if shown:
		wrapper.show_panel()
	else:
		wrapper.hide_panel()
