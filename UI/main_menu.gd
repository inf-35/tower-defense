extends Node

@export var play_button: Button
@export var difficulty_panel: Control
@export var normal_difficulty: Button
@export var hard_difficulty: Button

func _ready() -> void:
	difficulty_panel.visible = false
	play_button.pressed.connect(func():
		difficulty_panel.visible = true
	)
	
	normal_difficulty.pressed.connect(func():
		Phases.current_game_difficulty = Phases.GameDifficulty.NORMAL
		Phases.in_game = true
		get_tree().change_scene_to_file("res://island.tscn")
	)
	
	hard_difficulty.pressed.connect(func():
		Phases.current_game_difficulty = Phases.GameDifficulty.HARD
		Phases.in_game = true
		get_tree().change_scene_to_file("res://island.tscn")
	)
