extends Node2D
class_name TowerCombatLight

const GROUP_NAME: StringName = &"combat_tower_lights"
const DEFAULT_TEXTURE_SCALE: float = 2.0
const DEFAULT_ENERGY: float = 0.4
const DEFAULT_LIGHT_COLOR: Color = Color(1.0, 0.63, 0.2, 1.0)
const DEFAULT_ENVIRONMENT_ENERGY_MULTIPLIER: float = 1.0
const FADE_SECONDS: float = 0.6

@export var light_texture: Texture2D = preload("res://Content/CommonVisuals/combat_tower_light_texture.tres") ##native point-light texture used for the tower's local combat glow
@export_range(0.05, 4.0, 0.05) var texture_scale: float = DEFAULT_TEXTURE_SCALE ##radius multiplier for this marker's authored light texture
@export_range(0.0, 4.0, 0.01) var combat_energy: float = DEFAULT_ENERGY ##target light strength once combat-night has faded in

var _light_tween: Tween
var _combat_requested: bool = false
var _native_light: PointLight2D
var _light_color: Color = DEFAULT_LIGHT_COLOR
var _energy_multiplier: float = DEFAULT_ENVIRONMENT_ENERGY_MULTIPLIER
var available: bool = true:
	set(value):
		available = value
		set_combat_lit(_combat_requested, true)
var current_energy: float = 0.0:
	set(value):
		current_energy = maxf(value, 0.0)
		_apply_native_light_state()

func _ready() -> void:
	add_to_group(GROUP_NAME)
	_ensure_native_light()
	refresh_environment()
	var combat_active: bool = is_instance_valid(Run.phases) and Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE
	set_combat_lit(combat_active, true)

func _exit_tree() -> void:
	remove_from_group(GROUP_NAME)

func refresh_environment() -> void: ##reloads this marker's color and energy from the active environment profile
	_light_color = DEFAULT_LIGHT_COLOR
	_energy_multiplier = DEFAULT_ENVIRONMENT_ENERGY_MULTIPLIER
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile != null:
		_light_color = profile.night_light_color
		_energy_multiplier = maxf(profile.night_light_energy_multiplier, 0.0) * maxf(profile.night_max_light_energy, 0.0)
	_apply_native_light_state()

func set_combat_lit(active: bool, immediate: bool = false) -> void: ##fades this tower's light toward the current combat-lighting state
	_combat_requested = active
	var should_light: bool = active and available
	if is_instance_valid(_light_tween):
		_light_tween.kill()
	_fade_energy(combat_energy if should_light else 0.0, immediate)

func _fade_energy(target_energy: float, immediate: bool) -> void:
	if immediate:
		current_energy = target_energy
		return

	_light_tween = create_tween()
	_light_tween.tween_property(self, "current_energy", target_energy, FADE_SECONDS)

func _ensure_native_light() -> void: ##creates the godot 2d light node used by the native canvas lighting path
	if is_instance_valid(_native_light):
		return

	_native_light = PointLight2D.new()
	_native_light.name = "NativeCombatLight"
	_native_light.enabled = false
	_native_light.shadow_enabled = false
	add_child(_native_light)
	_apply_native_light_state()

func _apply_native_light_state() -> void: ##mirrors authored marker state onto the pointlight2d child
	if not is_inside_tree() and not is_instance_valid(_native_light):
		return
	_ensure_native_light()
	if not is_instance_valid(_native_light):
		return

	_native_light.texture = light_texture
	_native_light.texture_scale = texture_scale
	_native_light.color = _light_color
	_native_light.energy = current_energy * _energy_multiplier
	_native_light.enabled = available and light_texture != null and _native_light.energy > 0.001
