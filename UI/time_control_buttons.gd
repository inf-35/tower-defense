extends HBoxContainer
class_name TimeControlButtons

@export var pause_button: TextureButton
@export var base_button: TextureButton
@export var fast_forward_button: TextureButton

func _ready() -> void:
	pause_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.PAUSE))
	base_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.BASE))
	fast_forward_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.FAST_FORWARD))
	Clock.speed_changed.connect(_on_speed_changed)
	_on_speed_changed(Clock.speed_multiplier)

func _on_button_pressed(gamespeed: Clock.GameSpeed) -> void:
	UI.gamespeed_toggled.emit(gamespeed)


func _on_speed_changed(new_speed: float) -> void: ##keeps the currently active time control enlarged at the same size as a hovered icon
	_get_wrapper(pause_button).set_emphasized(is_equal_approx(new_speed, Clock.PAUSE_SPEED))
	_get_wrapper(base_button).set_emphasized(is_equal_approx(new_speed, Clock.BASE_SPEED))
	_get_wrapper(fast_forward_button).set_emphasized(is_equal_approx(new_speed, Clock.FAST_FORWARD_SPEED))


func _get_wrapper(button: TextureButton) -> AnimatableUI: ##time buttons sit directly under animatable wrappers in the scene
	return button.get_parent() as AnimatableUI
