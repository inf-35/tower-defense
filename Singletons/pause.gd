extends Node

const menu_scene := preload("res://UI/settings_menu/settings_menu.tscn")
var _current_menu_instance : SettingsMenu

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event):
	if event.is_action_pressed("menu"):
		if not is_instance_valid(_current_menu_instance):
			_current_menu_instance = menu_scene.instantiate()
			add_child(_current_menu_instance)
			
		if _current_menu_instance.visible:
			_current_menu_instance.back()
		else:
			_current_menu_instance.open_menu()
			
			if Phases.in_game:
				_current_menu_instance.enter_state(SettingsMenu.State.PAUSE)
			else:
				_current_menu_instance.enter_state(SettingsMenu.State.SETTINGS)
