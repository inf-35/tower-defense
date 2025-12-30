extends HBoxContainer
class_name TimeControlButtons

@export var pause_button: TextureButton
@export var base_button: TextureButton
@export var fast_forward_button: TextureButton

func _ready():
	pause_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.PAUSE))
	base_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.BASE))
	fast_forward_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.FAST_FORWARD))

func _on_button_pressed(gamespeed: Clock.GameSpeed):
	UI.gamespeed_toggled.emit(gamespeed)
