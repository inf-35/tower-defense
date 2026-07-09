extends HBoxContainer
class_name TimeControlButtons

const BATTLE_BUTTON_TEXT: String = "Battle (Space)"
const INACTIVE_BUTTON_ALPHA: float = 0.45

@export var battle_button: Button
@export var pause_button: TextureButton
@export var base_button: TextureButton
@export var fast_forward_button: TextureButton

var _building_phase_active: bool = true
var _tutorial_start_wave_locked: bool = false

func _ready() -> void:
	battle_button.text = BATTLE_BUTTON_TEXT
	battle_button.pressed.connect(_emit_start_wave)
	pause_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.PAUSE))
	base_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.BASE))
	fast_forward_button.pressed.connect(_on_button_pressed.bind(Clock.GameSpeed.FAST_FORWARD))
	UI.show_building_ui.connect(func():
		_building_phase_active = true
		_update_battle_button_state()
	)
	UI.hide_building_ui.connect(func():
		_building_phase_active = false
		_update_battle_button_state()
	)
	UI.tutorial_manager.start_wave_lock_changed.connect(func(locked: bool):
		_tutorial_start_wave_locked = locked
		_update_battle_button_state()
	)
	UI.tutorial_manager.register_element(TutorialContent.Element.START_WAVE_BUTTON, battle_button)
	Clock.speed_changed.connect(_on_speed_changed)
	_update_battle_button_state()
	_on_speed_changed(Clock.speed_multiplier)

func _input(event: InputEvent) -> void: ##allows starting combat from the keyboard without relying on button focus
	if not event.is_action_pressed("start_wave"):
		return
	if not _can_start_wave():
		return
	get_viewport().set_input_as_handled()
	_emit_start_wave()

func _update_battle_button_state() -> void: ##mirrors the real start-wave availability so the corner button and hotkey stay consistent
	battle_button.disabled = (not _building_phase_active) or _tutorial_start_wave_locked

func _can_start_wave() -> bool: ##matches the battle button's current availability
	return _building_phase_active and not battle_button.disabled

func _emit_start_wave() -> void: ##shares the same battle-start action between the corner button and the space-bar shortcut
	if not _can_start_wave():
		return
	UI.building_phase_ended.emit()

func _on_button_pressed(gamespeed: Clock.GameSpeed) -> void:
	UI.gamespeed_toggled.emit(gamespeed)


func _on_speed_changed(new_speed: float) -> void: ##keeps the active time control emphasized while dimming the inactive modes for clearer state readability
	_set_time_button_state(pause_button, is_equal_approx(new_speed, Clock.PAUSE_SPEED))
	_set_time_button_state(base_button, is_equal_approx(new_speed, Clock.BASE_SPEED))
	_set_time_button_state(fast_forward_button, is_equal_approx(new_speed, Clock.FAST_FORWARD_SPEED))

func _set_time_button_state(button: TextureButton, is_active: bool) -> void: ##applies both the size emphasis and the resting alpha treatment through the shared animatable wrapper
	var wrapper: AnimatableUI = _get_wrapper(button)
	wrapper.set_emphasized(is_active)
	wrapper.modulate.a = 1.0 if is_active else INACTIVE_BUTTON_ALPHA


func _get_wrapper(button: TextureButton) -> AnimatableUI: ##time buttons sit directly under animatable wrappers in the scene
	return button.get_parent() as AnimatableUI
