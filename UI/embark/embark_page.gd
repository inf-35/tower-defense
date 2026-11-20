extends Control
class_name EmbarkPage

signal cancelled
signal embark_requested(guild: GuildData, environment: Run.GameEnvironment, difficulty: Run.GameDifficulty)

@export var guild_options: Array[EmbarkGuildCard] = [] ##authored guild cards, each binding its own starting-package resource
@export var woods_option: EmbarkChoice ##woods map icon using the shared choice interaction
@export var winter_option: EmbarkChoice ##winter map icon; unavailable environments are not enumerated
@export var medium_option: EmbarkChoice ##medium maps to the existing normal difficulty without changing saved enum values
@export var hard_option: EmbarkChoice ##hard difficulty option
@export var title_label: Label ##selection-only summary in guild, environment, difficulty order
@export var guild_title: Label ##selected guild's canonical name
@export var guild_description: RichTextLabel ##selected guild's authored description
@export var environment_description: RichTextLabel ##offset map panel showing hovered content, lock requirements, or the selected map's description
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
		option.mouse_entered.connect(_show_locked_guild_description.bind(option))
		option.mouse_exited.connect(_refresh_guild_description)
	woods_option.pressed.connect(_select_environment.bind(Run.GameEnvironment.WOODS, woods_option))
	winter_option.pressed.connect(_select_environment.bind(Run.GameEnvironment.WINTER, winter_option))
	for environment: Run.GameEnvironment in [Run.GameEnvironment.WOODS, Run.GameEnvironment.WINTER]:
		var option: EmbarkChoice = woods_option if environment == Run.GameEnvironment.WOODS else winter_option
		option.mouse_entered.connect(_show_environment_description.bind(environment, option))
		option.mouse_exited.connect(_refresh_environment_description)
		option.focus_entered.connect(_show_environment_description.bind(environment, option))
		option.focus_exited.connect(_refresh_environment_description)
	medium_option.pressed.connect(_select_difficulty.bind(Run.GameDifficulty.NORMAL))
	hard_option.pressed.connect(_select_difficulty.bind(Run.GameDifficulty.HARD))
	woods_option.title = Run.get_environment_profile(Run.GameEnvironment.WOODS).display_name
	winter_option.title = Run.get_environment_profile(Run.GameEnvironment.WINTER).display_name
	woods_option.refresh_presentation()
	winter_option.refresh_presentation()
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
		option.refresh_unlock_state()
		option.reset()
	var choices: Array[EmbarkChoice] = [woods_option, winter_option, medium_option, hard_option, embark_button, cancel_button]
	for choice: EmbarkChoice in choices:
		choice.refresh_unlock_state()
		choice.reset()
	_refresh_guild_description()
	_refresh_environment_description()
	loadout.guild = null
	_refresh_summary()

func _on_guild_toggled(is_selected: bool, option: EmbarkGuildCard) -> void:
	if not is_selected or option.locked or _is_starting or _guild == option.guild:
		return
	_guild = option.guild
	_refresh_guild_description()
	loadout.guild = _guild
	_refresh_summary()

func _show_locked_guild_description(option: EmbarkGuildCard) -> void: ##shows the unlock condition without revealing an unavailable guild's starting package
	if not option.locked:
		return
	guild_title.text = "???"
	guild_description.text = KeywordService.wrap_text(option.get_unlock_requirement(), "bad")

func _refresh_guild_description() -> void: ##restores the current selection after a locked-card hover without changing the loadout
	guild_title.text = _guild.title if _guild != null else ""
	guild_description.text = _guild.description if _guild != null else ""

func _select_environment(environment: Run.GameEnvironment, option: EmbarkChoice) -> void:
	if _is_starting or option.locked:
		return
	_environment = environment
	_has_environment = true
	_refresh_environment_description()
	_refresh_summary()

func _show_environment_description(environment: Run.GameEnvironment, option: EmbarkChoice) -> void: ##previews the hovered map without changing selection or revealing locked map details
	environment_description.text = KeywordService.wrap_text(option.get_unlock_requirement(), "bad") if option.locked else Run.get_environment_profile(environment).description

func _refresh_environment_description() -> void: ##restores the selected map's description after hover or focus leaves another option
	environment_description.text = Run.get_environment_profile(_environment).description if _has_environment else ""

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

