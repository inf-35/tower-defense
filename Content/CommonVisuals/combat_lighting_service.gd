extends Node2D
class_name CombatLightingService

const DAY_COLOR: Color = Color.WHITE
const DEFAULT_NIGHT_COLOR: Color = Color(0.501, 0.589, 0.91, 1.0)
const DEFAULT_LIGHT_COLOR: Color = Color(1.0, 0.63, 0.2, 1.0)
const DEFAULT_NIGHT_TRANSITION_SECONDS: float = 0.5
const DEFAULT_UI_NIGHT_TINT_STRENGTH: float = 0.22
const UI_TINT_ROOT_PATHS: Array[String] = [
	"UI",
	"Tooltips",
]

class UiTintItemState extends RefCounted:
	var item_ref: WeakRef
	var base_self_modulate: Color = Color.WHITE

var _canvas_modulate: CanvasModulate
var _tint_tween: Tween
var _combat_lighting_active: bool = false
var _night_color: Color = DEFAULT_NIGHT_COLOR
var _native_light_color: Color = DEFAULT_LIGHT_COLOR
var _native_light_energy_multiplier: float = 1.0
var _night_transition_seconds: float = DEFAULT_NIGHT_TRANSITION_SECONDS
var _ui_night_tint_strength: float = DEFAULT_UI_NIGHT_TINT_STRENGTH
var _registered_ui_tint_items: Dictionary[int, UiTintItemState] = {}

func _ready() -> void:
	_setup_canvas_modulate()
	_connect_runtime_signals()
	_refresh_environment_profile()
	_apply_phase_state(true)

func _exit_tree() -> void:
	_restore_ui_tint_cache()
	_disconnect_runtime_signals()

func _setup_canvas_modulate() -> void: ##creates the single canvas-wide ambient tint used for combat night
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "CombatNightTint"
	_canvas_modulate.color = DAY_COLOR
	add_child(_canvas_modulate)

func _connect_runtime_signals() -> void: ##listens to phase changes without making lighting part of combat progression
	if not Run.environment_changed.is_connected(_on_environment_changed):
		Run.environment_changed.connect(_on_environment_changed)
	if not is_instance_valid(Run.phases):
		return
	if not Run.phases.combat_started.is_connected(_on_combat_started):
		Run.phases.combat_started.connect(_on_combat_started)
	if not Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.connect(_on_wave_ended)
	if not Run.phases.building_phase_started.is_connected(_on_building_phase_started):
		Run.phases.building_phase_started.connect(_on_building_phase_started)
	if not Run.run_ending.is_connected(_on_run_ending):
		Run.run_ending.connect(_on_run_ending)

func _disconnect_runtime_signals() -> void: ##clears runtime hooks when the island-owned visual service is destroyed
	if Run.environment_changed.is_connected(_on_environment_changed):
		Run.environment_changed.disconnect(_on_environment_changed)
	if is_instance_valid(Run.phases):
		if Run.phases.combat_started.is_connected(_on_combat_started):
			Run.phases.combat_started.disconnect(_on_combat_started)
		if Run.phases.wave_ended.is_connected(_on_wave_ended):
			Run.phases.wave_ended.disconnect(_on_wave_ended)
		if Run.phases.building_phase_started.is_connected(_on_building_phase_started):
			Run.phases.building_phase_started.disconnect(_on_building_phase_started)
	if Run.run_ending.is_connected(_on_run_ending):
		Run.run_ending.disconnect(_on_run_ending)

func _on_environment_changed(_game_environment: Run.GameEnvironment) -> void: ##defers profile refresh until save restoration has finished updating the rest of the run state
	_refresh_environment_profile.call_deferred()

func _refresh_environment_profile() -> void: ##rebinds every environment-authored native lighting value after a loaded run replaces the startup environment
	var profile: EnvironmentProfile = Run.get_environment_profile()
	_night_color = DEFAULT_NIGHT_COLOR
	_native_light_color = DEFAULT_LIGHT_COLOR
	_native_light_energy_multiplier = 1.0
	_night_transition_seconds = DEFAULT_NIGHT_TRANSITION_SECONDS
	_ui_night_tint_strength = DEFAULT_UI_NIGHT_TINT_STRENGTH
	if profile != null:
		_night_color = profile.night_ambient_color
		_native_light_color = profile.night_light_color
		_native_light_energy_multiplier = maxf(profile.night_light_energy_multiplier, 0.0) * maxf(profile.night_max_light_energy, 0.0)
		_night_transition_seconds = profile.night_transition_seconds
		_ui_night_tint_strength = profile.night_ui_tint_strength

	_configure_tower_lights()
	_apply_phase_state(true)

func _on_combat_started(_wave_number: int) -> void:
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	_apply_night(false)
	_set_tower_lights_active(true, false)

func _on_wave_ended(_wave_number: int) -> void:
	_apply_daylight(false)
	_set_tower_lights_active(false, false)

func _on_building_phase_started(_wave_number: int) -> void:
	_apply_daylight(false)
	_set_tower_lights_active(false, false)

func _on_run_ending() -> void:
	_apply_daylight(true)
	_restore_ui_tint_cache()
	_set_tower_lights_active(false, true)

func _apply_phase_state(immediate: bool) -> void: ##syncs native lighting to the current phase for fresh services and phase transitions
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	var combat_active: bool = is_instance_valid(Run.phases) and Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE
	if combat_active:
		_apply_night(immediate)
	else:
		_apply_daylight(immediate)
	_set_tower_lights_active(combat_active, immediate)

func _apply_night(immediate: bool) -> void: ##fades the world canvas into the authored combat-night hue
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	refresh_ui_tint_cache()
	_fade_canvas_modulate(_night_color, immediate)

func _apply_daylight(immediate: bool) -> void: ##returns the world canvas to its normal unlit presentation
	_fade_canvas_modulate(DAY_COLOR, immediate)

func _fade_canvas_modulate(target_color: Color, immediate: bool) -> void:
	if not is_instance_valid(_canvas_modulate):
		return
	if is_instance_valid(_tint_tween):
		_tint_tween.kill()
	if immediate:
		_set_canvas_modulate_color(target_color)
		if _colors_equal_approx(target_color, DAY_COLOR):
			_restore_ui_tint_cache()
		return

	_tint_tween = create_tween()
	_tint_tween.tween_method(_set_canvas_modulate_color, _canvas_modulate.color, target_color, _night_transition_seconds)
	_tint_tween.tween_callback(_on_canvas_modulate_fade_finished.bind(target_color))

func _set_canvas_modulate_color(color: Color) -> void: ##applies ambient tint and refreshes registered ui tint in the same frame
	_canvas_modulate.color = color
	_apply_registered_ui_tints()

func _on_canvas_modulate_fade_finished(target_color: Color) -> void: ##restores centrally tracked canvas items once daylight has fully returned
	if _colors_equal_approx(target_color, DAY_COLOR):
		_restore_ui_tint_cache()

func _configure_tower_lights() -> void: ##pushes environment-authored colour and energy into every native tower light marker
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			(node as TowerCombatLight).configure_light(_native_light_color, _native_light_energy_multiplier)

func _set_tower_lights_active(active: bool, immediate: bool) -> void: ##broadcasts combat-light state to authored native tower light markers already in the scene
	if DebugAssistant.disable_combat_lighting:
		active = false

	_combat_lighting_active = active
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			var tower_light := node as TowerCombatLight
			tower_light.configure_light(_native_light_color, _native_light_energy_multiplier)
			tower_light.set_combat_lit(active, immediate)

func refresh_ui_tint_cache() -> void: ##rebuilds the list of hud controls that should inherit a partial combat-night tint
	if DebugAssistant.disable_combat_lighting:
		_restore_ui_tint_cache()
		return
	if _ui_night_tint_strength <= 0.0:
		_restore_ui_tint_cache()
		return

	_restore_ui_tint_cache()
	for root: Node in _get_ui_tint_roots():
		_track_ui_tint_items(root)

	_apply_registered_ui_tints()

func _get_ui_tint_roots() -> Array[Node]: ##returns the narrow in-run ui surfaces that should receive the partial night color
	var roots: Array[Node] = []
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return roots

	for root_path: String in UI_TINT_ROOT_PATHS:
		var root: Node = Run.references.island.get_node_or_null(root_path)
		if is_instance_valid(root):
			roots.append(root)

	return roots

func _track_ui_tint_items(node: Node) -> void: ##records control canvas items under the authored hud roots without touching world-space overlays
	if node is Control:
		_track_ui_tint_item(node as Control)

	for child: Node in node.get_children():
		_track_ui_tint_items(child)

func _track_ui_tint_item(item: Control) -> void: ##stores one ui item's original self-modulate so combat tint can be reversed cleanly
	if not is_instance_valid(item):
		return
	if _registered_ui_tint_items.has(item.get_instance_id()):
		return

	var state := UiTintItemState.new()
	state.item_ref = weakref(item)
	state.base_self_modulate = item.self_modulate
	_registered_ui_tint_items[item.get_instance_id()] = state
	_apply_registered_ui_tint_state(state)

func _restore_ui_tint_cache() -> void: ##restores hud self-modulates after combat night tint has fully faded out
	for instance_id: int in _registered_ui_tint_items:
		var state: UiTintItemState = _registered_ui_tint_items[instance_id]
		var item: CanvasItem = state.item_ref.get_ref() as CanvasItem
		if is_instance_valid(item):
			item.self_modulate = state.base_self_modulate
	_registered_ui_tint_items.clear()

func _apply_registered_ui_tints() -> void: ##refreshes hud colors against the current night-fade progress while culling freed controls
	var stale_ids: Array[int] = []
	for instance_id: int in _registered_ui_tint_items:
		var state: UiTintItemState = _registered_ui_tint_items[instance_id]
		if not _apply_registered_ui_tint_state(state):
			stale_ids.append(instance_id)

	for instance_id: int in stale_ids:
		_registered_ui_tint_items.erase(instance_id)

func _apply_registered_ui_tint_state(state: UiTintItemState) -> bool: ##applies partial night hue to one cached hud item and reports whether it still exists
	var item: CanvasItem = state.item_ref.get_ref() as CanvasItem
	if not is_instance_valid(item):
		return false

	item.self_modulate = _get_ui_tinted_color(state.base_self_modulate)
	return true

func _get_ui_tinted_color(base_color: Color) -> Color: ##blends hud colors toward the combat-night hue according to the current ambient fade progress
	var night_progress: float = _get_night_tint_progress()
	if night_progress <= 0.0:
		return base_color

	var tint_target: Color = Color(_night_color.r, _night_color.g, _night_color.b, base_color.a)
	return base_color.lerp(tint_target, _ui_night_tint_strength * night_progress)

func _get_night_tint_progress() -> float: ##derives a 0-1 ui tint amount from the same canvas color driving world nighttime
	if not is_instance_valid(_canvas_modulate):
		return 0.0

	var denominator: float = absf(DAY_COLOR.r - _night_color.r) + absf(DAY_COLOR.g - _night_color.g) + absf(DAY_COLOR.b - _night_color.b)
	if denominator <= 0.0:
		return 0.0

	var ambient: Color = _canvas_modulate.color
	var numerator: float = absf(DAY_COLOR.r - ambient.r) + absf(DAY_COLOR.g - ambient.g) + absf(DAY_COLOR.b - ambient.b)
	return clampf(numerator / denominator, 0.0, 1.0)

func apply_debug_visual_flags() -> void: ##applies the current debug lighting switch to an already-live island service
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	_apply_phase_state(true)

func _apply_disabled_lighting_state() -> void:
	_combat_lighting_active = false
	if is_instance_valid(_canvas_modulate):
		_set_canvas_modulate_color(DAY_COLOR)
	_restore_ui_tint_cache()
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			(node as TowerCombatLight).set_combat_lit(false, true)

func _colors_equal_approx(a: Color, b: Color) -> bool: ##compares colors channel-by-channel so process gating does not depend on optional variant helpers
	return is_equal_approx(a.r, b.r)\
		and is_equal_approx(a.g, b.g)\
		and is_equal_approx(a.b, b.b)\
		and is_equal_approx(a.a, b.a)
