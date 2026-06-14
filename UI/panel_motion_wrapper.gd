extends Control
class_name PanelMotionWrapper

@export var anchor_node: Control ##stable layout anchor that owns the canonical on-screen rect for this panel wrapper
@export var content: Control ##real panel content reparented under this wrapper so motion stays isolated from the panel internals
@export var hidden_offset: Vector2 = Vector2.ZERO ##where the wrapper should travel relative to the anchor when hidden
@export var show_duration: float = 0.24 ##default tween duration used when moving the panel into view
@export var hide_duration: float = 0.2 ##default tween duration used when moving the panel out of view

var _motion_progress_internal: float = 0.0
var motion_progress: float:
	get:
		return _motion_progress_internal
	set(value):
		_motion_progress_internal = clampf(value, 0.0, 1.0)
		_apply_layout()

var _motion_tween: Tween

func _ready() -> void: ##keeps the wrapper rect slaved to its anchor so resize math stays delegated to godot instead of hand-maintained offsets
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_layout()

func _process(_delta: float) -> void: ##refreshes wrapper rect from the anchor each frame so shown and hidden states survive viewport/layout changes cleanly
	_apply_layout()

func show_panel(duration: float = -1.0) -> void: ##tweens the wrapper back onto its anchor rect
	_animate_to(0.0, show_duration if duration < 0.0 else duration)

func hide_panel(duration: float = -1.0) -> void: ##tweens the wrapper out toward its configured hidden offset
	_animate_to(1.0, hide_duration if duration < 0.0 else duration)

func snap_shown() -> void: ##immediately restores the wrapper to its anchor rect without tweening
	if is_instance_valid(_motion_tween):
		_motion_tween.kill()
	_motion_tween = null
	motion_progress = 0.0

func snap_hidden() -> void: ##immediately places the wrapper at its hidden offset without tweening
	if is_instance_valid(_motion_tween):
		_motion_tween.kill()
	_motion_tween = null
	motion_progress = 1.0

func _animate_to(target_progress: float, duration: float) -> void:
	if is_instance_valid(_motion_tween):
		_motion_tween.kill()

	if is_equal_approx(motion_progress, target_progress):
		motion_progress = target_progress
		_motion_tween = null
		return

	_motion_tween = create_tween()
	_motion_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_motion_tween.tween_property(self, "motion_progress", target_progress, duration)
	_motion_tween.finished.connect(func(): _motion_tween = null)

func _apply_layout() -> void:
	if not is_instance_valid(anchor_node):
		return

	size = anchor_node.size
	position = anchor_node.position + hidden_offset * motion_progress
