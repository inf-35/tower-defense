extends Node

const menu_scene := preload("res://UI/settings_menu/settings_menu.tscn")
signal attached_effect_icons_changed(is_enabled: bool)

var _current_menu_instance: SettingsMenu
var menu_back_handler: Callable = Callable() ##owner callback used by escape when the settings menu is closed
var show_all_health_bars: bool = false
var show_attached_effect_icons: bool = true:
	set(is_enabled):
		if show_attached_effect_icons == is_enabled:
			return
		show_attached_effect_icons = is_enabled
		attached_effect_icons_changed.emit(show_attached_effect_icons)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveLoad.load_profile()

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu"):
		return
	if is_instance_valid(_current_menu_instance) and _current_menu_instance.visible:
		_current_menu_instance.back()
	elif menu_back_handler.is_valid():
		menu_back_handler.call()
	else:
		open_menu()
	get_viewport().set_input_as_handled()

func open_menu(initial_state: SettingsMenu.State = SettingsMenu.State.PAUSE) -> void: ##opens one shared menu; pause requests outside gameplay use settings instead
	if not is_instance_valid(_current_menu_instance):
		_current_menu_instance = menu_scene.instantiate()
		add_child(_current_menu_instance)

	if initial_state == SettingsMenu.State.PAUSE and not (is_instance_valid(Run.phases) and Run.phases.in_game):
		initial_state = SettingsMenu.State.SETTINGS
	_current_menu_instance.open_menu(initial_state)

func enter_state(state: SettingsMenu.State) -> void:
	_current_menu_instance.enter_state(state)
