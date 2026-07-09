extends BaseButton
class_name ClickyButton

const SELF_HOVER_SCALE: Vector2 = Vector2(1.04, 1.04)
const SELF_HOVER_DURATION: float = 0.11

var _motion_target: AnimatableUI
var _last_disabled_state: bool = false
var _self_hover_tween: Tween

func _init() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	#connect this button's own built-in signals to its handler functions
	self.mouse_entered.connect(_clicky_on_mouse_entered)
	self.mouse_entered.connect(_clicky_forward_mouse_entered)
	self.mouse_exited.connect(_clicky_forward_mouse_exited)
	self.pressed.connect(_clicky_on_pressed)

func _enter_tree() -> void:
	if not resized.is_connected(_update_pivot):
		resized.connect(_update_pivot)
	call_deferred("_update_pivot")
	if not is_instance_valid(_motion_target):
		_motion_target = _find_animatable_descendant(self)
		if is_instance_valid(_motion_target):
			_motion_target.hover_enabled = false
	_last_disabled_state = disabled
	_refresh_cursor_shape()
	set_process(true)

func _process(_delta: float) -> void:
	if _last_disabled_state == disabled:
		return
	_last_disabled_state = disabled
	_refresh_cursor_shape()

func set_motion_target(motion_target: AnimatableUI) -> void: ##allows callers to reuse the standard hover-expand behavior without reimplementing signal forwarding
	_motion_target = motion_target
	if is_instance_valid(_motion_target):
		_motion_target.hover_enabled = false

func _refresh_cursor_shape() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND

#--- signal handlers ---

#called when the mouse enters the button's bounds
func _clicky_on_mouse_entered() -> void:
	#do not play a sound if the button is disabled
	if self.disabled:
		return

	#delegate the actual playing of the sound to the central audioservice
	Audio.play_sound(ID.Sounds.BUTTON_HOVER_SOUND, -5.0)
	
	
#called when the button is pressed
func _clicky_on_pressed() -> void:
	#the 'disabled' check is handled by the button itself, so we don't need it here

	Audio.play_sound(ID.Sounds.BUTTON_CLICK_SOUND, -1.0)

func _clicky_forward_mouse_entered() -> void:
	if disabled:
		return
	if is_instance_valid(_motion_target):
		_motion_target.set_hover_active(true)
		return
	_tween_self_scale(SELF_HOVER_SCALE)

func _clicky_forward_mouse_exited() -> void:
	if is_instance_valid(_motion_target):
		_motion_target.set_hover_active(false)
		return
	_tween_self_scale(Vector2.ONE)

func _update_pivot() -> void:
	pivot_offset = size / 2.0

func _tween_self_scale(target_scale: Vector2) -> void:
	if _self_hover_tween:
		_self_hover_tween.kill()
	_self_hover_tween = create_tween()
	_self_hover_tween.tween_property(self, "scale", target_scale, SELF_HOVER_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _find_animatable_descendant(node: Node) -> AnimatableUI:
	for child: Node in node.get_children():
		if child is AnimatableUI:
			return child
		var nested: AnimatableUI = _find_animatable_descendant(child)
		if is_instance_valid(nested):
			return nested
	return null
