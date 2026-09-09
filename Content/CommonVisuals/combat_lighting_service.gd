extends Node2D
class_name CombatLightingService

const COMBAT_LIGHT_MASK_PAINTER_SCRIPT := preload("res://Content/CommonVisuals/combat_light_mask_painter.gd")
@export var light_overlay_material: ShaderMaterial = preload("res://Content/CommonVisuals/combat_light_overlay.tres") ##authored brightness response; copied per island so the viewport texture remains run-owned

const DAY_COLOR: Color = Color.WHITE
const DEFAULT_NIGHT_COLOR: Color = Color(0.501, 0.589, 0.91, 1.0)
const DEFAULT_LIGHT_COLOR: Color = Color(1.0, 0.63, 0.2, 1.0)
const DEFAULT_NIGHT_TRANSITION_SECONDS: float = 0.5
const DEFAULT_UI_NIGHT_TINT_STRENGTH: float = 0.22
const LIGHT_OVERLAY_LAYER: int = 0
const LIGHT_MASK_MARGIN: float = 32.0
const UI_TINT_ROOT_PATHS: Array[String] = [
	"UI",
	"Tooltips",
]

class UiTintItemState extends RefCounted:
	var item_ref: WeakRef
	var base_self_modulate: Color = Color.WHITE

var _canvas_modulate: CanvasModulate
var _tint_tween: Tween
var _overlay_layer: CanvasLayer
var _back_buffer_copy: BackBufferCopy
var _overlay_rect: ColorRect
var _overlay_material: ShaderMaterial
var _mask_viewport: SubViewport
var _mask_painter: CombatLightMaskPainter
var _combat_lighting_active: bool = false
var _world_style_active: bool = false
var _night_color: Color = DEFAULT_NIGHT_COLOR
var _light_color: Color = DEFAULT_LIGHT_COLOR
var _light_energy_multiplier: float = 1.0
var _night_transition_seconds: float = DEFAULT_NIGHT_TRANSITION_SECONDS
var _ui_night_tint_strength: float = DEFAULT_UI_NIGHT_TINT_STRENGTH
var _registered_ui_tint_items: Dictionary[int, UiTintItemState] = {}

func _ready() -> void:
	_setup_canvas_modulate()
	_setup_shader_lighting()
	_connect_runtime_signals()
	_apply_phase_state(true)
	set_process(false)

func _exit_tree() -> void:
	_restore_ui_tint_cache()
	_disconnect_runtime_signals()

func _setup_canvas_modulate() -> void: ##creates the single canvas-wide ambient tint used for combat night
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "CombatNightTint"
	_canvas_modulate.color = DAY_COLOR
	add_child(_canvas_modulate)

func _setup_shader_lighting() -> void: ##creates the offscreen light mask and one capped screen-space overlay
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "CombatLightMaskViewport"
	_mask_viewport.disable_3d = true
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask_viewport)

	_mask_painter = COMBAT_LIGHT_MASK_PAINTER_SCRIPT.new()
	_mask_painter.name = "CombatLightMaskPainter"
	_mask_viewport.add_child(_mask_painter)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "CombatLightOverlayLayer"
	_overlay_layer.layer = LIGHT_OVERLAY_LAYER
	add_child(_overlay_layer)

	_back_buffer_copy = BackBufferCopy.new()
	_back_buffer_copy.name = "CombatLightBackBufferCopy"
	_back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_overlay_layer.add_child(_back_buffer_copy)

	_overlay_material = light_overlay_material.duplicate() as ShaderMaterial
	_overlay_material.set_shader_parameter("light_mask", _mask_viewport.get_texture())
	_configure_environment_style()

	_overlay_rect = ColorRect.new()
	_overlay_rect.name = "CombatLightOverlay"
	_overlay_rect.material = _overlay_material
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.anchor_right = 1.0
	_overlay_rect.anchor_bottom = 1.0
	_overlay_rect.visible = _world_style_active
	_overlay_layer.add_child(_overlay_rect)
	_sync_overlay_size()

func _configure_environment_style() -> void: ##loads the active environment's day grade and night-light response into the shared compositor
	var profile: EnvironmentProfile = Run.get_environment_profile()
	_world_style_active = profile != null and profile.world_style_enabled and profile.world_style_strength > 0.0
	_overlay_material.set_shader_parameter(&"world_style_enabled", _world_style_active)
	_overlay_material.set_shader_parameter(&"ambient_color", DAY_COLOR)
	_overlay_material.set_shader_parameter(&"light_strength", 0.0)
	if profile == null:
		return

	_overlay_material.set_shader_parameter(&"world_style_strength", profile.world_style_strength)
	_overlay_material.set_shader_parameter(&"world_tone_input", profile.world_tone_input)
	_overlay_material.set_shader_parameter(&"world_tone_output", profile.world_tone_output)
	_overlay_material.set_shader_parameter(&"neutral_chroma_scale", profile.world_neutral_chroma_scale)
	_overlay_material.set_shader_parameter(&"accent_chroma_scale", profile.world_accent_chroma_scale)
	_overlay_material.set_shader_parameter(&"accent_chroma_start", profile.world_accent_chroma_start)
	_overlay_material.set_shader_parameter(&"accent_chroma_end", profile.world_accent_chroma_end)
	_night_color = profile.night_ambient_color
	_light_color = profile.night_light_color
	_light_energy_multiplier = profile.night_light_energy_multiplier
	_night_transition_seconds = profile.night_transition_seconds
	_ui_night_tint_strength = profile.night_ui_tint_strength
	_overlay_material.set_shader_parameter(&"max_light_energy", profile.night_max_light_energy)
	_overlay_material.set_shader_parameter(&"surface_light_strength", profile.night_surface_light_strength)
	_overlay_material.set_shader_parameter(&"surface_tint_strength", profile.night_surface_tint_strength)
	_overlay_material.set_shader_parameter(&"lit_chroma_scale", profile.night_lit_chroma_scale)
	_overlay_material.set_shader_parameter(&"additive_bloom_strength", profile.night_additive_bloom_strength)
	_overlay_material.set_shader_parameter(&"dark_pixel_response", profile.night_dark_pixel_response)
	_overlay_material.set_shader_parameter(&"light_luminance_power", profile.night_luminance_power)

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

func _refresh_environment_profile() -> void: ##rebinds every environment-authored lighting value after a loaded run replaces the startup environment
	if not is_instance_valid(_overlay_material):
		return
	_configure_environment_style()
	if is_instance_valid(_overlay_rect):
		_overlay_rect.visible = _world_style_active
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

func _apply_phase_state(immediate: bool) -> void: ##syncs lighting to the current phase for fresh services and phase transitions
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	var combat_active: bool = is_instance_valid(Run.phases) and Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE
	if combat_active:
		_apply_night(immediate)
	else:
		_apply_daylight(immediate)
	_set_tower_lights_active(combat_active, immediate)

func _process(_delta: float) -> void:
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	_refresh_light_mask()

func _apply_night(immediate: bool) -> void: ##fades the canvas into the authored combat-night hue
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	refresh_ui_tint_cache()
	_fade_canvas_modulate(_night_color, immediate)

func _apply_daylight(immediate: bool) -> void: ##returns the canvas to its normal unlit presentation
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

func _set_canvas_modulate_color(color: Color) -> void: ##applies the ambient tint and refreshes the registered ui tint in the same frame
	_canvas_modulate.color = color
	if is_instance_valid(_overlay_material):
		_overlay_material.set_shader_parameter(&"ambient_color", color)
	_apply_registered_ui_tints()

func _on_canvas_modulate_fade_finished(target_color: Color) -> void: ##restores centrally tracked canvas items once daylight has fully returned
	if _colors_equal_approx(target_color, DAY_COLOR):
		_restore_ui_tint_cache()

func _set_tower_lights_active(active: bool, immediate: bool) -> void: ##broadcasts combat-light state to authored tower light markers already in the scene
	if DebugAssistant.disable_combat_lighting:
		active = false

	_combat_lighting_active = active
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			(node as TowerCombatLight).set_combat_lit(active, immediate)

	set_process(active or _has_visible_light_markers() or _has_active_ui_tints())
	_refresh_light_mask()

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
	set_process(_combat_lighting_active or _has_visible_light_markers() or _has_active_ui_tints())

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
	set_process(true)

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

func _refresh_light_mask() -> void: ##draws all tower light markers into one screen-space mask for the capped overlay shader
	if not is_instance_valid(_mask_viewport) or not is_instance_valid(_mask_painter):
		return
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	_sync_overlay_size()
	var lights: Array[Dictionary] = _collect_screen_lights()
	var should_render: bool = not lights.is_empty()
	var should_process: bool = _combat_lighting_active or should_render or _has_active_ui_tints()
	_overlay_material.set_shader_parameter(&"light_strength", 1.0 if should_render else 0.0)
	_overlay_rect.visible = should_render or _world_style_active
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if should_process else SubViewport.UPDATE_DISABLED
	_mask_painter.set_lights(lights)
	if not should_process:
		set_process(false)

func apply_debug_visual_flags() -> void: ##applies the current debug lighting switch to an already-live island service
	if DebugAssistant.disable_combat_lighting:
		_apply_disabled_lighting_state()
		return

	_apply_phase_state(true)

func _apply_disabled_lighting_state() -> void:
	_combat_lighting_active = false
	if is_instance_valid(_canvas_modulate):
		_set_canvas_modulate_color(DAY_COLOR)
	if is_instance_valid(_overlay_rect):
		_overlay_rect.visible = _world_style_active
	if is_instance_valid(_overlay_material):
		_overlay_material.set_shader_parameter(&"light_strength", 0.0)
	if is_instance_valid(_mask_viewport):
		_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_restore_ui_tint_cache()
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			(node as TowerCombatLight).set_combat_lit(false, true)
	set_process(false)

func _has_active_ui_tints() -> bool: ##keeps the service alive while hud tint has cached items and the night fade is still visible
	if _ui_night_tint_strength <= 0.0 or _registered_ui_tint_items.is_empty():
		return false
	return _get_night_tint_progress() > 0.0

func _colors_equal_approx(a: Color, b: Color) -> bool: ##compares colors channel-by-channel so process gating does not depend on optional variant helpers
	return is_equal_approx(a.r, b.r)\
		and is_equal_approx(a.g, b.g)\
		and is_equal_approx(a.b, b.b)\
		and is_equal_approx(a.a, b.a)

func _collect_screen_lights() -> Array[Dictionary]: ##converts world-space tower markers into the screen-space data consumed by the mask painter
	var lights: Array[Dictionary] = []
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var pixels_per_world_unit: float = (canvas_transform.x.length() + canvas_transform.y.length()) * 0.5
	var viewport_size: Vector2 = Vector2(_mask_viewport.size)

	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if not (node is TowerCombatLight):
			continue

		var tower_light := node as TowerCombatLight
		if not tower_light.has_visible_light():
			continue

		var screen_position: Vector2 = canvas_transform * tower_light.global_position
		var screen_radius: float = tower_light.get_world_radius() * pixels_per_world_unit
		if not _screen_circle_visible(screen_position, screen_radius, viewport_size):
			continue

		lights.append(tower_light.get_mask_draw_data(
			screen_position,
			screen_radius,
			_light_color,
			_light_energy_multiplier
		))

	return lights

func _has_visible_light_markers() -> bool: ##keeps the overlay processing until fade-outs have reached zero
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight and (node as TowerCombatLight).has_visible_light():
			return true
	return false

func _screen_circle_visible(position: Vector2, radius: float, viewport_size: Vector2) -> bool:
	return position.x >= -radius - LIGHT_MASK_MARGIN and position.y >= -radius - LIGHT_MASK_MARGIN and position.x <= viewport_size.x + radius + LIGHT_MASK_MARGIN and position.y <= viewport_size.y + radius + LIGHT_MASK_MARGIN

func _sync_overlay_size() -> void: ##keeps the mask viewport aligned with the current window so mask uv matches screen uv
	var visible_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_size := Vector2i(int(ceil(visible_size.x)), int(ceil(visible_size.y)))
	if _mask_viewport.size != viewport_size:
		_mask_viewport.size = viewport_size
