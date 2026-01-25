extends CanvasLayer
class_name SettingsMenu

# --- UI References ---
@export var master_slider: HSlider
@export var sfx_slider: HSlider
@export var music_slider: HSlider
@export var fullscreen_toggle: CheckButton
@export var back_button: Button

@export var resume_button: Button
@export var settings_button: Button
@export var save_and_quit_button: Button

@export var settings_root: Control # The container to hide/show
@export var pause_root: Control

# state
enum State {
	PAUSE, #the pause menu that shows up ingame
	SETTINGS, #the settings menu
}
var state: State

# --- Audio Bus Indices ---
var _bus_master: int
var _bus_sfx: int
var _bus_music: int

# extra-environmental state
var _saved_gamespeed: float

const AUDIO_POWER: float = 2.0 ##root of power curve of the audio
 
signal closed()

func _ready() -> void:
	# 1. Cache Audio Bus Indices (Safety check if names change)
	_bus_master = AudioServer.get_bus_index("Master")
	_bus_sfx = AudioServer.get_bus_index("SFX")
	_bus_music = AudioServer.get_bus_index("Music")
	
	# 2. Initialize UI State from Current Settings
	_load_current_settings()
	
	# 3. Connect Signals
	master_slider.value_changed.connect(_on_volume_changed.bind(_bus_master))
	sfx_slider.value_changed.connect(_on_volume_changed.bind(_bus_sfx))
	music_slider.value_changed.connect(_on_volume_changed.bind(_bus_music))
	
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	back_button.pressed.connect(back)
	resume_button.pressed.connect(func(): close_menu())
	settings_button.pressed.connect(func(): enter_state(State.SETTINGS))
	save_and_quit_button.pressed.connect(func(): _on_save_and_quit())
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Start hidden
	visible = false

func open_menu() -> void:
	visible = true
	_saved_gamespeed = Clock.speed_multiplier
	Clock.speed_multiplier = 0.0

func close_menu() -> void:
	visible = false
	Clock.speed_multiplier = _saved_gamespeed
	closed.emit()

func back() -> void:
	if state == State.SETTINGS and Phases.in_game:
		enter_state(State.PAUSE)
		return
		
	close_menu()
	
func enter_state(input_state: State) -> void:
	match input_state:
		State.SETTINGS:
			settings_root.visible = true
			pause_root.visible = false
		State.PAUSE:
			settings_root.visible = false
			pause_root.visible = true
	
	state = input_state
# --- Internal Logic ---

func _load_current_settings() -> void:
	# Volume (Convert DB to 0-1 linear if your sliders are 0-1, or 0-100)
	# Assuming Sliders are 0.0 to 1.0
	master_slider.value = pow(db_to_linear(AudioServer.get_bus_volume_db(_bus_master)), -AUDIO_POWER)
	sfx_slider.value = pow(db_to_linear(AudioServer.get_bus_volume_db(_bus_sfx)), -AUDIO_POWER)
	music_slider.value = pow(db_to_linear(AudioServer.get_bus_volume_db(_bus_music)), -AUDIO_POWER)
	
	# Fullscreen
	var mode = DisplayServer.window_get_mode()
	fullscreen_toggle.button_pressed = (mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _on_volume_changed(value: float, bus_index: int) -> void:
	# Convert linear slider (0-1) to Decibels
	# Use linear_to_db which maps 0 to -INF (Silence)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(pow(value, AUDIO_POWER)))
	
	# Mute if 0 to prevent faint audio issues
	AudioServer.set_bus_mute(bus_index, value < 0.01)

func _on_fullscreen_toggled(is_fullscreen: bool) -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Optional: Center window
		# DisplayServer.window_set_position(...)
		
func _on_save_and_quit():
	Phases.in_game = false
	SaveLoad.save_game()
	get_tree().change_scene_to_file("res://main_menu.tscn")
	close_menu()
