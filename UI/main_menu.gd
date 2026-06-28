extends Node

@export var play_button: Button
@export var settings_button: Button
@export var continue_button: Button
@export var feedback_button: Button
@export var difficulty_panel: Control
@export var normal_difficulty: Button
@export var hard_difficulty: Button

const FEEDBACK_FORM_URL: String = "https://docs.google.com/forms/d/e/1FAIpQLSdjTLjsxete1nBg6uRjVjMCB3220uPqmYzGuMnReDQ72I6yAg/viewform?usp=header"

func _ready() -> void:
	difficulty_panel.visible = false
	if SaveLoad.has_save_file():
		continue_button.visible = true

	settings_button.pressed.connect(func():
		Pause.open_menu()
	)

	continue_button.pressed.connect(func():
		get_tree().change_scene_to_file("res://island.tscn")
	)

	feedback_button.pressed.connect(func():
		OS.shell_open(FEEDBACK_FORM_URL)
	)

	play_button.pressed.connect(func():
		difficulty_panel.visible = true
	)

	normal_difficulty.pressed.connect(func():
		SaveLoad.delete_save()
		Run.set_pending_game_difficulty(Run.GameDifficulty.NORMAL)
		get_tree().change_scene_to_file("res://island.tscn")
	)

	hard_difficulty.pressed.connect(func():
		SaveLoad.delete_save()
		Run.set_pending_game_difficulty(Run.GameDifficulty.HARD)
		get_tree().change_scene_to_file("res://island.tscn")
	)
