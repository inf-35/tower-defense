extends Node2D
class_name TowerCombatLight

const GROUP_NAME: StringName = &"combat_tower_lights"
const DEFAULT_TEXTURE_SCALE: float = 2.0
const DEFAULT_ENERGY: float = 0.4
const FADE_SECONDS: float = 0.6

@export var light_texture: Texture2D = preload("res://Content/CommonVisuals/combat_tower_light_texture.tres") ##mask texture drawn into the shared combat-light buffer
@export_range(0.05, 4.0, 0.05) var texture_scale: float = DEFAULT_TEXTURE_SCALE ##radius multiplier for this marker's authored light texture
@export_range(0.0, 4.0, 0.01) var combat_energy: float = DEFAULT_ENERGY ##target light strength once combat-night has faded in

var _light_tween: Tween
var _combat_requested: bool = false
var _available: bool = true
var current_energy: float = 0.0

func _ready() -> void:
	add_to_group(GROUP_NAME)
	set_combat_lit(_is_combat_phase(), true)

func _exit_tree() -> void:
	remove_from_group(GROUP_NAME)

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

func has_visible_light() -> bool: ##answers whether this marker should contribute to the shared light mask
	return is_available() and current_energy > 0.001 and light_texture != null

func get_world_radius() -> float: ##keeps shader-light size aligned with the previous point-light texture footprint
	if light_texture == null:
		return 0.0

	var texture_size: Vector2 = light_texture.get_size()
	return maxf(texture_size.x, texture_size.y) * texture_scale * 0.5

func get_mask_draw_data(screen_position: Vector2, screen_radius: float, global_light_color: Color, energy_multiplier: float) -> Dictionary: ##packages local light shape and environment-owned appearance for the shared mask painter
	return {
		"position": screen_position,
		"radius": screen_radius,
		"color": global_light_color,
		"energy": current_energy * maxf(energy_multiplier, 0.0),
		"texture": light_texture,
	}

func _is_combat_phase() -> bool:
	return is_instance_valid(Run.phases) and Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE

func _get_parent_tower() -> Tower: ##finds the owning tower even when the marker is attached under a presentation child
	var parent_node: Node = get_parent()
	while is_instance_valid(parent_node):
		if parent_node is Tower:
			return parent_node as Tower
		parent_node = parent_node.get_parent()

	return null
