extends Node

const menu_scene := preload("res://UI/settings_menu/settings_menu.tscn")
var _current_menu_instance: SettingsMenu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event) -> void:
	if event.is_action_pressed("menu"):
		if not is_instance_valid(_current_menu_instance):
			_current_menu_instance = menu_scene.instantiate()
			add_child(_current_menu_instance)

		if _current_menu_instance.visible:
			_current_menu_instance.back()
		else:
			open_menu()

func open_menu() -> void:
	if not is_instance_valid(_current_menu_instance):
		_current_menu_instance = menu_scene.instantiate()
		add_child(_current_menu_instance)

	_current_menu_instance.open_menu()

	if Run.phases.in_game:
		_current_menu_instance.enter_state(SettingsMenu.State.PAUSE)
	else:
		_current_menu_instance.enter_state(SettingsMenu.State.SETTINGS)

func enter_state(state: SettingsMenu.State) -> void:
	_current_menu_instance.enter_state(state)
