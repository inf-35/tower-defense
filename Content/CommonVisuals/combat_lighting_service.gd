extends Node2D
class_name CombatLightingService

const DAY_COLOR: Color = Color.WHITE
const DEFAULT_NIGHT_COLOR: Color = Color(0.501, 0.589, 0.91, 1.0)
const DEFAULT_NIGHT_TRANSITION_SECONDS: float = 1.0
const DEFAULT_UI_NIGHT_TINT_STRENGTH: float = 0.22
const UNIT_LIGHTING_WARMUP_SHADERS: Array[Shader] = [
	preload("res://Shaders/unit_effects.gdshader"),
	preload("res://Shaders/swept_shadow.gdshader"),
	preload("res://Shaders/silhouette.gdshader"),
]
const UI_TINT_ROOT_PATHS: Array[String] = [
	"UI",
	"Tooltips",
]

class UiTintItemState extends RefCounted:
	var item_ref: WeakRef
	var base_self_modulate: Color = Color.WHITE

enum ShadowState {
	DAY,
	TO_NIGHT,
	NIGHT,
	TO_DAY,
}

var _canvas_modulate: CanvasModulate
var _tint_tween: Tween
var _combat_lighting_active: bool = false
var _night_color: Color = DEFAULT_NIGHT_COLOR
var _night_transition_seconds: float = DEFAULT_NIGHT_TRANSITION_SECONDS
var _ui_night_tint_strength: float = DEFAULT_UI_NIGHT_TINT_STRENGTH
var _registered_ui_tint_items: Dictionary[int, UiTintItemState] = {}
var _shadow_refresh_queued: bool = false
var _shadow_components: Array[ShadowComponent] = []
var _shadow_state: ShadowState = ShadowState.DAY
var _shadow_night_mix: float = 0.0
var _shadow_transition_tween: Tween

func _ready() -> void:
	_setup_canvas_modulate()
	_connect_runtime_signals()
	_refresh_environment_profile()
	_apply_phase_state(true)

func _exit_tree() -> void:
	_restore_ui_tint_cache()
	_disconnect_runtime_signals()

func warm_up_shaders() -> void: ##renders day and night material variants during loading without changing the live world's lighting or phase
	var island := get_parent() as Island
	var path_material: Material = Run.references.path_renderer.path_wash_layer.material
	var materials: Array[Material] = [
		null,
		island.terrain_renderer.terrain_rect.material,
		island.terrain_renderer.background_stain_rect.material,
		island.preview_renderer.terrain_rect.material,
		path_material,
	]
	for shader: Shader in UNIT_LIGHTING_WARMUP_SHADERS:
		var material := ShaderMaterial.new()
		material.shader = shader
		materials.append(material)

	var viewport := SubViewport.new()
	viewport.name = "LightingShaderWarmup"
	viewport.size = Vector2i(64, 64)
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	#the texture is not displayed, so the default update-when-visible mode would skip rendering.
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	for index: int in range(materials.size()):
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.material = materials[index]
		sprite.position = Vector2(12.0 + float(index % 4) * 12.0, 12.0 + floorf(float(index) / 4.0) * 12.0)
		sprite.scale = Vector2(8.0, 8.0)
		viewport.add_child(sprite)

	#route strokes use polygon geometry, which needs a separate variant from sprite rectangles.
	var line_materials: Array[Material] = [null, path_material]
	for index: int in range(line_materials.size()):
		var line := Line2D.new()
		line.material = line_materials[index]
		line.points = PackedVector2Array([Vector2(8.0, 40.0 + float(index) * 8.0), Vector2(56.0, 40.0 + float(index) * 8.0)])
		line.width = 2.0
		line.antialiased = true
		viewport.add_child(line)

	var light := PointLight2D.new()
	light.texture = texture
	light.texture_scale = 128.0
	light.position = Vector2(32.0, 32.0)
	light.shadow_enabled = false
	light.enabled = false
	viewport.add_child(light)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	light.enabled = true
	await RenderingServer.frame_post_draw
	viewport.free()

func _setup_canvas_modulate() -> void: ##creates the single canvas-wide ambient tint used for combat night
	_canvas_modulate = CanvasModulate.new()
	_canvas_modulate.name = "CombatNightTint"
	_canvas_modulate.color = DAY_COLOR
	add_child(_canvas_modulate)

func _connect_runtime_signals() -> void: ##listens to phase changes without making lighting part of combat progression
	if not Run.environment_changed.is_connected(_on_environment_changed):
		Run.environment_changed.connect(_on_environment_changed)
	var island := get_parent() as Island
	if island != null and not island.tower_changed.is_connected(_on_tower_changed):
		island.tower_changed.connect(_on_tower_changed)
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
	var island := get_parent() as Island
	if island != null and island.tower_changed.is_connected(_on_tower_changed):
		island.tower_changed.disconnect(_on_tower_changed)
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

func _on_tower_changed(_tower_position: Vector2i) -> void: ##defers nighttime shadow reassignment until created or removed light nodes finish their tree transition
	if _shadow_refresh_queued:
		return
	_shadow_refresh_queued = true
	_flush_shadow_lighting_refresh.call_deferred()

func _flush_shadow_lighting_refresh() -> void: ##coalesces bulk tower construction or teardown into one full shadow reassignment
	_shadow_refresh_queued = false
	if not _combat_lighting_active:
		return
	var has_active_lights: bool = _refresh_shadow_assignments()
	if not has_active_lights:
		_set_shadow_target(false, true)
	elif _shadow_state == ShadowState.DAY or _shadow_state == ShadowState.TO_DAY:
		_set_shadow_target(true, true)

func _refresh_environment_profile() -> void: ##rebinds every environment-authored native lighting value after a loaded run replaces the startup environment
	var profile: EnvironmentProfile = Run.get_environment_profile()
	_night_color = DEFAULT_NIGHT_COLOR
	_night_transition_seconds = DEFAULT_NIGHT_TRANSITION_SECONDS
	_ui_night_tint_strength = DEFAULT_UI_NIGHT_TINT_STRENGTH
	if profile != null:
		_night_color = profile.night_ambient_color
		_night_transition_seconds = profile.night_transition_seconds
		_ui_night_tint_strength = profile.night_ui_tint_strength

	_refresh_tower_lights()
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

func _refresh_tower_lights() -> void: ##asks existing native tower light markers to reload the active environment profile
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			(node as TowerCombatLight).refresh_environment()

func _set_tower_lights_active(active: bool, immediate: bool) -> void: ##broadcasts combat-light state to authored native tower light markers already in the scene
	if DebugAssistant.disable_combat_lighting:
		active = false

	_combat_lighting_active = active
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if node is TowerCombatLight:
			var tower_light := node as TowerCombatLight
			tower_light.set_combat_lit(active, immediate)
	if active:
		var has_active_lights: bool = _refresh_shadow_assignments()
		_set_shadow_target(has_active_lights, immediate)
	else:
		_set_shadow_target(false, immediate)

func register_shadow(shadow: ShadowComponent) -> void: ##adds one persistent caster renderer to the shared shadow pool and applies current global state
	if not is_instance_valid(shadow) or _shadow_components.has(shadow):
		return
	_shadow_components.append(shadow)
	if _shadow_night_mix > 0.0:
		var active_lights: Array[TowerCombatLight] = _collect_shadow_lights()
		_assign_shadow_sources(shadow, active_lights)
	else:
		shadow.set_night_projections([])
	shadow.set_night_mix(_shadow_night_mix)

func unregister_shadow(shadow: ShadowComponent) -> void: ##removes a caster renderer from the shared pool without touching unrelated shadows
	_shadow_components.erase(shadow)

func _collect_shadow_lights() -> Array[TowerCombatLight]: ##returns authored tower lights currently eligible to project local shadows
	var active_lights: Array[TowerCombatLight] = []
	for node: Node in get_tree().get_nodes_in_group(TowerCombatLight.GROUP_NAME):
		if not (node is TowerCombatLight):
			continue
		var tower_light := node as TowerCombatLight
		if tower_light.available and tower_light.light_texture != null and tower_light.combat_energy > 0.001:
			active_lights.append(tower_light)
	return active_lights

func _refresh_shadow_assignments() -> bool: ##reassigns the two nearest sources for every pooled caster and reports whether any source exists
	var active_lights: Array[TowerCombatLight] = _collect_shadow_lights()
	for index: int in range(_shadow_components.size() - 1, -1, -1):
		var shadow: ShadowComponent = _shadow_components[index]
		if not is_instance_valid(shadow):
			_shadow_components.remove_at(index)
			continue
		_assign_shadow_sources(shadow, active_lights)
	return not active_lights.is_empty()

func _assign_shadow_sources(shadow: ShadowComponent, active_lights: Array[TowerCombatLight]) -> void: ##selects and sends the nearest two light positions to one pooled caster
	if active_lights.is_empty():
		shadow.set_night_projections([])
		return

	var nearest_light: TowerCombatLight
	var second_nearest_light: TowerCombatLight
	var nearest_distance_squared: float = INF
	var second_nearest_distance_squared: float = INF
	for tower_light: TowerCombatLight in active_lights:
		var distance_squared: float = shadow.global_position.distance_squared_to(tower_light.global_position)
		if distance_squared < nearest_distance_squared:
			second_nearest_light = nearest_light
			second_nearest_distance_squared = nearest_distance_squared
			nearest_light = tower_light
			nearest_distance_squared = distance_squared
		elif distance_squared < second_nearest_distance_squared:
			second_nearest_light = tower_light
			second_nearest_distance_squared = distance_squared

	var light_positions: Array[Vector2] = [nearest_light.global_position]
	if second_nearest_light != null:
		light_positions.append(second_nearest_light.global_position)
	shadow.set_night_projections(light_positions)

func _set_shadow_target(target_night: bool, immediate: bool) -> void: ##moves the single global shadow state machine toward day or night
	var transition_state: ShadowState = ShadowState.TO_NIGHT if target_night else ShadowState.TO_DAY
	var settled_state: ShadowState = ShadowState.NIGHT if target_night else ShadowState.DAY
	var target_mix: float = 1.0 if target_night else 0.0
	if is_instance_valid(_shadow_transition_tween):
		if _shadow_state == transition_state and not immediate:
			return
		_shadow_transition_tween.kill()
		_shadow_transition_tween = null
	if immediate or is_equal_approx(_shadow_night_mix, target_mix):
		_set_shadow_night_mix(target_mix)
		_shadow_state = settled_state
		return

	_shadow_state = transition_state
	var transition_duration: float = _night_transition_seconds * absf(target_mix - _shadow_night_mix)
	_shadow_transition_tween = create_tween()
	_shadow_transition_tween.set_trans(Tween.TRANS_SINE)
	_shadow_transition_tween.set_ease(Tween.EASE_IN_OUT)
	_shadow_transition_tween.tween_method(_set_shadow_night_mix, _shadow_night_mix, target_mix, maxf(transition_duration, 0.001))
	_shadow_transition_tween.tween_callback(_finish_shadow_transition.bind(settled_state, target_mix))

func _set_shadow_night_mix(night_mix: float) -> void: ##broadcasts one transition value across the pooled caster renderers
	_shadow_night_mix = clampf(night_mix, 0.0, 1.0)
	for index: int in range(_shadow_components.size() - 1, -1, -1):
		var shadow: ShadowComponent = _shadow_components[index]
		if not is_instance_valid(shadow):
			_shadow_components.remove_at(index)
			continue
		shadow.set_night_mix(_shadow_night_mix)

func _finish_shadow_transition(settled_state: ShadowState, target_mix: float) -> void: ##commits the endpoint of the shared transition and releases its Tween
	_shadow_transition_tween = null
	_shadow_state = settled_state
	_set_shadow_night_mix(target_mix)

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
	_set_shadow_target(false, true)

func _colors_equal_approx(a: Color, b: Color) -> bool: ##compares colors channel-by-channel so process gating does not depend on optional variant helpers
	return is_equal_approx(a.r, b.r)\
		and is_equal_approx(a.g, b.g)\
		and is_equal_approx(a.b, b.b)\
		and is_equal_approx(a.a, b.a)
