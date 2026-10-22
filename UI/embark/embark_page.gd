extends Control
class_name EmbarkPage

signal cancelled
signal embark_requested(guild: GuildData, environment: Run.GameEnvironment, difficulty: Run.GameDifficulty)

@export var guild_options: Array[EmbarkGuildCard] = [] ##authored guild cards, each binding its own starting-package resource
@export var woods_option: EmbarkChoice ##placeholder woods environment option
@export var winter_option: EmbarkChoice ##placeholder winter environment option; unavailable environments are not enumerated
@export var medium_option: EmbarkChoice ##medium maps to the existing normal difficulty without changing saved enum values
@export var hard_option: EmbarkChoice ##hard difficulty option
@export var title_label: Label ##selection-only summary in guild, environment, difficulty order
@export var guild_title: Label ##selected guild's canonical name
@export var guild_description: RichTextLabel ##selected guild's authored description
@export var loadout: EmbarkLoadout ##display-only starting-package presenter
@export var embark_button: EmbarkChoice ##enabled only after all three choices are made
@export var cancel_button: EmbarkChoice ##returns to the title menu without committing the draft

var _guild: GuildData
var _environment: Run.GameEnvironment
var _difficulty: Run.GameDifficulty
var _has_environment: bool = false
var _has_difficulty: bool = false
var _is_starting: bool = false

func _ready() -> void:
	for option: EmbarkGuildCard in guild_options:
		option.toggled.connect(_on_guild_toggled.bind(option))
	woods_option.pressed.connect(_select_environment.bind(Run.GameEnvironment.WOODS))
	winter_option.pressed.connect(_select_environment.bind(Run.GameEnvironment.WINTER))
	medium_option.pressed.connect(_select_difficulty.bind(Run.GameDifficulty.NORMAL))
	hard_option.pressed.connect(_select_difficulty.bind(Run.GameDifficulty.HARD))
	woods_option.title = Run.get_environment_profile(Run.GameEnvironment.WOODS).display_name
	winter_option.title = Run.get_environment_profile(Run.GameEnvironment.WINTER).display_name
	woods_option.caption.text = woods_option.title
	winter_option.caption.text = winter_option.title
	embark_button.pressed.connect(_confirm)
	cancel_button.pressed.connect(cancel)
	_reset_selection()

func open() -> void: ##starts a fresh local draft instead of inheriting pending run defaults
	_reset_selection()
	show()

func cancel() -> void: ##hides the form without changing run settings or the existing save
	if _is_starting:
		return
	hide()
	cancelled.emit()

func _reset_selection() -> void: ##resets native pressed state and animation state together without emitting selection events
	_guild = null
	_has_environment = false
	_has_difficulty = false
	_is_starting = false
	for option: EmbarkGuildCard in guild_options:
		option.reset()
	var choices: Array[EmbarkChoice] = [woods_option, winter_option, medium_option, hard_option, embark_button, cancel_button]
	for choice: EmbarkChoice in choices:
		choice.reset()
	guild_title.text = ""
	guild_description.text = ""
	loadout.guild = null
	_refresh_summary()

func _on_guild_toggled(is_selected: bool, option: EmbarkGuildCard) -> void:
	if not is_selected or _is_starting or _guild == option.guild:
		return
	_guild = option.guild
	guild_title.text = _guild.title
	guild_description.text = _guild.description
	loadout.guild = _guild
	_refresh_summary()

func _select_environment(environment: Run.GameEnvironment) -> void:
	if _is_starting:
		return
	_environment = environment
	_has_environment = true
	_refresh_summary()

func _select_difficulty(difficulty: Run.GameDifficulty) -> void:
	if _is_starting:
		return
	_difficulty = difficulty
	_has_difficulty = true
	_refresh_summary()

func _refresh_summary() -> void: ##omits unselected fields entirely; the same draft gates confirmation
	var parts: PackedStringArray = PackedStringArray()
	if _guild != null:
		parts.append(_guild.title)
	if _has_environment:
		parts.append(Run.get_environment_profile(_environment).display_name)
	if _has_difficulty:
		parts.append("Hard" if _difficulty == Run.GameDifficulty.HARD else "Medium")
	title_label.text = " - ".join(parts)
	embark_button.disabled = _is_starting or _guild == null or not _has_environment or not _has_difficulty
	embark_button.modulate.a = 0.5 if embark_button.disabled else 1.0
	cancel_button.disabled = _is_starting

func _confirm() -> void: ##emits one complete snapshot; granting content remains the new-run bootstrap's responsibility
	if _is_starting or _guild == null or not _has_environment or not _has_difficulty:
		return
	_is_starting = true
	_refresh_summary()
	embark_requested.emit(_guild, _environment, _difficulty)

