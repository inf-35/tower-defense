extends Node

@export var play_button: Button ##main new-run entrypoint on the title screen
@export var settings_button: Button ##opens the shared settings menu from the title screen
@export var continue_button: Button ##resumes the current save if one exists
@export var feedback_button: Button ##opens the external feedback form
@export var environment_panel: Control ##shown first so new runs choose an environment before their guild
@export var woods_environment: Button ##starts the woods branch of new-run setup
@export var winter_environment: Button ##starts the winter branch of new-run setup
@export var guild_panel: Control ##shown between environment and difficulty selection
@export var testers_button: Button ##selects the authored testers starting package
@export var pioneers_button: Button ##selects the authored pioneers starting package
@export var testers_guild: GuildData ##starting package bound to the testers choice
@export var pioneers_guild: GuildData ##starting package bound to the pioneers choice
@export var difficulty_panel: Control ##shown after guild selection to finish new-run setup
@export var normal_difficulty: Button ##starts a normal-difficulty run
@export var hard_difficulty: Button ##starts a hard-difficulty run

const FEEDBACK_FORM_URL: String = "https://docs.google.com/forms/d/e/1FAIpQLSdjTLjsxete1nBg6uRjVjMCB3220uPqmYzGuMnReDQ72I6yAg/viewform?usp=header"

func _ready() -> void: ##wires the title-screen buttons into the existing run boot flow
	environment_panel.visible = false
	guild_panel.visible = false
	difficulty_panel.visible = false
	if SaveLoad.has_save_file():
		continue_button.visible = true

	settings_button.pressed.connect(_open_settings_menu)
	continue_button.pressed.connect(_continue_game)
	feedback_button.pressed.connect(_open_feedback_form)
	play_button.pressed.connect(_show_environment_panel)
	woods_environment.pressed.connect(_select_woods_environment)
	winter_environment.pressed.connect(_select_winter_environment)
	testers_button.text = testers_guild.title
	testers_button.tooltip_text = testers_guild.description
	testers_button.pressed.connect(_select_guild.bind(testers_guild))
	pioneers_button.text = pioneers_guild.title
	pioneers_button.tooltip_text = pioneers_guild.description
	pioneers_button.pressed.connect(_select_guild.bind(pioneers_guild))
	normal_difficulty.pressed.connect(_start_normal_game)
	hard_difficulty.pressed.connect(_start_hard_game)

func _open_settings_menu() -> void:
	Pause.open_menu()

func _continue_game() -> void:
	get_tree().change_scene_to_file("res://island.tscn")

func _open_feedback_form() -> void:
	OS.shell_open(FEEDBACK_FORM_URL)

func _show_environment_panel() -> void: ##restarts new-run selection from the environment stage
	environment_panel.visible = true
	guild_panel.visible = false
	difficulty_panel.visible = false
	var environment_buttons: Array[Button] = [woods_environment, winter_environment]
	_animate_choice_buttons(environment_buttons)

func _select_woods_environment() -> void:
	_select_environment(Run.GameEnvironment.WOODS)

func _select_winter_environment() -> void:
	_select_environment(Run.GameEnvironment.WINTER)

func _select_environment(game_environment: Run.GameEnvironment) -> void: ##stores the environment choice and presents the authored guild options
	Run.set_pending_game_environment(game_environment)
	environment_panel.visible = false
	guild_panel.visible = true
	difficulty_panel.visible = false
	var guild_buttons: Array[Button] = [testers_button, pioneers_button]
	_animate_choice_buttons(guild_buttons)

func _select_guild(guild: GuildData) -> void: ##stores the next run's starting package without granting it while browsing the menu
	Run.pending_guild = guild
	guild_panel.visible = false
	difficulty_panel.visible = true
	var difficulty_buttons: Array[Button] = [normal_difficulty, hard_difficulty]
	_animate_choice_buttons(difficulty_buttons)

func _animate_choice_buttons(buttons: Array[Button]) -> void: ##stagger-plays each choice button's entrance from above
	for button: Button in buttons:
		var animation: AnimatableUI = button.get_parent() as AnimatableUI
		if is_instance_valid(animation):
			animation.animate_entrance()

func _start_normal_game() -> void:
	_start_new_game(Run.GameDifficulty.NORMAL)

func _start_hard_game() -> void:
	_start_new_game(Run.GameDifficulty.HARD)

func _start_new_game(game_difficulty: Run.GameDifficulty) -> void: ##keeps new-run boot identical after the environment choice is locked in
	SaveLoad.delete_save()
	Run.set_pending_game_difficulty(game_difficulty)
	get_tree().change_scene_to_file("res://island.tscn")
