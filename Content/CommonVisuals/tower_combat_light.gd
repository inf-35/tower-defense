extends Node2D
class_name TowerCombatLight

const GROUP_NAME: StringName = &"combat_tower_lights"
const DEFAULT_TEXTURE_SCALE: float = 2.0
const DEFAULT_ENERGY: float = 0.4
const FADE_SECONDS: float = 0.6

@export var light_texture: Texture2D = preload("res://Content/CommonVisuals/combat_tower_light_texture.tres") ##native point-light texture used for the tower's local combat glow
@export_range(0.05, 4.0, 0.05) var texture_scale: float = DEFAULT_TEXTURE_SCALE ##radius multiplier for this marker's authored light texture
@export_range(0.0, 4.0, 0.01) var combat_energy: float = DEFAULT_ENERGY ##target light strength once combat-night has faded in

var _light_tween: Tween
var _combat_requested: bool = false
var _available: bool = true
var _native_light: PointLight2D
var _light_color: Color = Color.WHITE
var _energy_multiplier: float = 1.0
var current_energy: float = 0.0:
	set(value):
		current_energy = maxf(value, 0.0)
		_apply_native_light_state()

func _ready() -> void:
	add_to_group(GROUP_NAME)
	_ensure_native_light()
	set_combat_lit(_is_combat_phase(), true)

func _exit_tree() -> void:
	remove_from_group(GROUP_NAME)

func configure_light(color: Color, energy_multiplier: float) -> void: ##applies the active environment's native light colour and energy scale without changing local authored range
	_light_color = color
	_energy_multiplier = maxf(energy_multiplier, 0.0)
	_apply_native_light_state()

func set_available(available: bool) -> void: ##lets tower state changes suppress light without disconnecting the visual helper
	_available = available
	set_combat_lit(_combat_requested, true)

func set_combat_lit(active: bool, immediate: bool = false) -> void: ##fades this tower's light toward the current combat-lighting state
	_combat_requested = active
	var should_light: bool = active and is_available()
	if is_instance_valid(_light_tween):
		_light_tween.kill()
	_fade_energy(combat_energy if should_light else 0.0, immediate)

func _fade_energy(target_energy: float, immediate: bool) -> void:
	if immediate:
		current_energy = target_energy
		return

	_light_tween = create_tween()
	_light_tween.tween_property(self, "current_energy", target_energy, FADE_SECONDS)

func is_available() -> bool: ##checks local opt-out state plus common tower lifecycle state without requiring tower.gd hooks
	if not _available:
		return false

	var tower: Tower = _get_parent_tower()
	if tower != null:
		if tower.abstractive or tower.environmental or tower.hostile:
			return false
		return tower.current_state == Tower.State.ACTIVE

	return true

func has_visible_light() -> bool: ##answers whether this marker should emit native light
	return is_available() and current_energy > 0.001 and light_texture != null

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
	_native_light.enabled = has_visible_light() and _native_light.energy > 0.001

func _is_combat_phase() -> bool:
	return is_instance_valid(Run.phases) and Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE

func _get_parent_tower() -> Tower: ##finds the owning tower even when the marker is attached under a presentation child
	var parent_node: Node = get_parent()
	while is_instance_valid(parent_node):
		if parent_node is Tower:
			return parent_node as Tower
		parent_node = parent_node.get_parent()

	return null
