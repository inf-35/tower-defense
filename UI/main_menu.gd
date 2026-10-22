extends Node

@export var play_button: Button ##main new-run entrypoint on the title screen
@export var settings_button: Button ##opens the shared settings menu from the title screen
@export var index_button: Button ##opens the shared index page directly from the title screen
@export var continue_button: Button ##resumes the current save if one exists
@export var feedback_button: Button ##opens the external feedback form
@export var embark_page: EmbarkPage ##authored new-run setup page
@export var title_content: Control ##title-screen controls hidden while choosing a run

const FEEDBACK_FORM_URL: String = "https://docs.google.com/forms/d/e/1FAIpQLSdjTLjsxete1nBg6uRjVjMCB3220uPqmYzGuMnReDQ72I6yAg/viewform?usp=header"

var _scene_change_requested: bool = false

func _ready() -> void: ##connects title actions and the authored embark page to run startup
	if SaveLoad.has_save_file():
		continue_button.visible = true

	settings_button.pressed.connect(_open_settings_menu)
	index_button.pressed.connect(_open_index)
	continue_button.pressed.connect(_continue_game)
	feedback_button.pressed.connect(_open_feedback_form)
	play_button.pressed.connect(_open_embark)
	embark_page.cancelled.connect(_on_embark_cancelled)
	embark_page.embark_requested.connect(_on_embark_requested)

func _exit_tree() -> void:
	_clear_embark_back_handler()

func _open_settings_menu() -> void:
	Pause.open_menu()

func _open_index() -> void: ##uses the same page, escape handling, and back navigation as the pause menu
	Pause.open_menu(SettingsMenu.State.INDEX)

func _continue_game() -> void:
	get_tree().change_scene_to_file("res://island.tscn")

func _open_feedback_form() -> void:
	OS.shell_open(FEEDBACK_FORM_URL)

func _open_embark() -> void: ##shows the authored run setup page and routes escape to its cancel action
	title_content.visible = false
	Pause.menu_back_handler = Callable(embark_page, "cancel")
	embark_page.open()

func _on_embark_cancelled() -> void: ##restores title controls after setup is dismissed
	_clear_embark_back_handler()
	title_content.visible = true

func _on_embark_requested(guild: GuildData, game_environment: Run.GameEnvironment, game_difficulty: Run.GameDifficulty) -> void: ##commits validated selections once and starts a fresh run
	if _scene_change_requested:
		return
	if guild == null:
		push_warning("MainMenu: rejected embark without a guild")
		return
	if not Run.GameEnvironment.values().has(int(game_environment)):
		push_warning("MainMenu: rejected embark with an invalid environment")
		return
	if not Run.GameDifficulty.values().has(int(game_difficulty)):
		push_warning("MainMenu: rejected embark with an invalid difficulty")
		return

	_scene_change_requested = true
	_clear_embark_back_handler()
	Run.pending_guild = guild
	Run.set_pending_game_environment(game_environment)
	Run.set_pending_game_difficulty(game_difficulty)

	var island_scene: PackedScene = load("res://island.tscn") as PackedScene
	var next_scene: Node = island_scene.instantiate() if island_scene != null else null
	if next_scene == null:
		_scene_change_requested = false
		_open_embark()
		push_error("MainMenu: failed to prepare the island scene")
		return

	SaveLoad.delete_save()
	if SaveLoad.has_save_file():
		next_scene.free()
		_scene_change_requested = false
		_open_embark()
		push_error("MainMenu: could not remove the previous save; new run cancelled")
		return

	var change_error: Error = get_tree().change_scene_to_node(next_scene)
	if change_error != OK:
		next_scene.free()
		_scene_change_requested = false
		_open_embark()
		push_error("MainMenu: failed to change to island scene (%d)" % change_error)
		return

func _clear_embark_back_handler() -> void: ##clears escape only while this page owns the callback
	if Pause.menu_back_handler == Callable(embark_page, "cancel"):
		Pause.menu_back_handler = Callable()
