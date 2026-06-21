extends RefCounted
class_name TintService

enum BlendMode {
	MODULATE,
	OVERLAY,
}

const LAYER_SIDE_TINT: int = 0
const LAYER_STATE_VISUAL: int = 1
const LAYER_STATUS: int = 2
const LAYER_DISABLED: int = 3
const LAYER_RITE_PULSE: int = 4
const LAYER_HIT_FLASH: int = 5
const LAYER_RESERVED_0: int = 6
const LAYER_RESERVED_1: int = 7
const LAYER_COUNT: int = 8

const HIT_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const UNIT_EFFECTS_SHADER: Shader = preload("res://Shaders/unit_effects.gdshader")

static var _shared_unit_effects_material: ShaderMaterial

var _owner: Node
var _root_graphics: Sprite2D
var _base_graphics_modulate: Color = Color.WHITE

var _layer_colors: Array[Color] = []
var _layer_strengths: Array[float] = []
var _layer_affect_alpha: Array[bool] = []
var _layer_blend_modes: Array[int] = []
var _layer_active: Array[bool] = []
var _layer_tweens: Array = []

func _init() -> void: ##primes the fixed layer tables immediately so units can queue tint state before graphics are fully prepared
	_reset_layer_state()

func initialise(owner: Node, root_graphics: Sprite2D) -> void: ##binds the service to a unit graphics root and snapshots its authored modulate for layered recomposition
	_owner = owner
	_root_graphics = root_graphics
	if not is_instance_valid(_root_graphics):
		return

	_base_graphics_modulate = _root_graphics.modulate
	_apply_tints()

func set_tint_layer(layer: int, color: Color, strength: float = 1.0, affect_alpha: bool = false, blend_mode: int = BlendMode.MODULATE) -> void: ##sets one fixed tint layer and immediately recomposes the unit graphics through either the modulate or shader-overlay path
	_assert_valid_layer(layer)
	_kill_layer_tween(layer)
	if is_zero_approx(strength):
		_clear_tint_layer_internal(layer)
		return
	_set_tint_layer_internal(layer, color, strength, affect_alpha, blend_mode)

func clear_tint_layer(layer: int) -> void: ##clears one fixed tint layer and immediately recomposes the unit graphics modulate
	_assert_valid_layer(layer)
	_kill_layer_tween(layer)
	_clear_tint_layer_internal(layer)

func tween_tint_layer(
	layer: int,
	from_color: Color,
	to_color: Color,
	duration: float,
	affect_alpha: bool = false,
	trans: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
	ignore_pause: bool = false,
	blend_mode: int = BlendMode.MODULATE
) -> void: ##tweens the target color of one fixed tint layer while preserving that layer's current strength and touchpoint
	_assert_valid_layer(layer)
	_kill_layer_tween(layer)
	if not is_instance_valid(_owner):
		return

	var strength: float = _layer_strengths[layer] if _layer_active[layer] else 1.0
	_set_tint_layer_internal(layer, from_color, strength, affect_alpha, blend_mode)

	var tween: Tween = _owner.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_layer_tweens[layer] = tween
	tween.tween_method(_set_tint_color.bind(layer, affect_alpha), from_color, to_color, duration)\
		.set_trans(trans).set_ease(ease)
	tween.finished.connect(func():
		_layer_tweens[layer] = null
	)

func tween_tint_strength(
	layer: int,
	from: float,
	to: float,
	duration: float,
	trans: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
	ignore_pause: bool = false,
	blend_mode: BlendMode = BlendMode.MODULATE,
) -> void: ##tweens the strength of one fixed tint layer while preserving its current color and alpha behavior
	_assert_valid_layer(layer)
	_kill_layer_tween(layer)
	if not is_instance_valid(_owner):
		return

	if not _layer_active[layer]:
		_set_tint_layer_internal(layer, Color.WHITE, from, false, blend_mode)
	else:
		_layer_strengths[layer] = clampf(from, 0.0, 1.0)
		_apply_tints()

	var tween: Tween = _owner.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_layer_tweens[layer] = tween
	tween.tween_method(_set_tint_strength.bind(layer), from, to, duration)\
		.set_trans(trans).set_ease(ease)
	tween.finished.connect(func():
		_layer_tweens[layer] = null
		if is_zero_approx(_layer_strengths[layer]):
			_clear_tint_layer_internal(layer)
	)

func pulse_tint_layer(
	layer: int,
	color: Color,
	peak_strength: float,
	ramp_in_duration: float,
	ramp_out_duration: float,
	affect_alpha: bool = false,
	trans: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
	ignore_pause: bool = false,
	blend_mode: int = BlendMode.MODULATE
) -> void: ##plays a simple in-out pulse on one fixed tint layer through either tint touchpoint
	_assert_valid_layer(layer)
	_kill_layer_tween(layer)
	if not is_instance_valid(_owner):
		return

	_set_tint_layer_internal(layer, color, 0.0, affect_alpha, blend_mode)

	var tween: Tween = _owner.create_tween()
	if ignore_pause:
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_layer_tweens[layer] = tween
	tween.tween_method(_set_tint_strength.bind(layer), 0.0, peak_strength, ramp_in_duration)\
		.set_trans(trans).set_ease(ease)
	tween.tween_method(_set_tint_strength.bind(layer), peak_strength, 0.0, ramp_out_duration)\
		.set_trans(trans).set_ease(ease)
	tween.finished.connect(func():
		_layer_tweens[layer] = null
		_clear_tint_layer_internal(layer)
	)

func play_hit_flash(duration: float = 0.25, ignore_pause: bool = false) -> void: ##plays the standard hit flash by pushing the sprite toward white through the shader overlay path
	set_tint_layer(LAYER_HIT_FLASH, HIT_FLASH_COLOR, 1.0, false, BlendMode.OVERLAY)
	tween_tint_strength(LAYER_HIT_FLASH, 1.0, 0.0, duration, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, ignore_pause, BlendMode.OVERLAY)

func _set_tint_layer_internal(layer: int, color: Color, strength: float, affect_alpha: bool, blend_mode: BlendMode) -> void: ##updates one layer without disturbing any tween bookkeeping
	_layer_active[layer] = true
	_layer_colors[layer] = color
	_layer_strengths[layer] = clampf(strength, 0.0, 1.0)
	_layer_affect_alpha[layer] = affect_alpha
	_layer_blend_modes[layer] = blend_mode
	_apply_tints()

func _clear_tint_layer_internal(layer: int) -> void: ##clears one layer without disturbing any tween bookkeeping
	_layer_active[layer] = false
	_layer_colors[layer] = Color.WHITE
	_layer_strengths[layer] = 0.0
	_layer_affect_alpha[layer] = false
	_layer_blend_modes[layer] = BlendMode.MODULATE
	_apply_tints()

func _set_tint_color(color: Color, layer: int, affect_alpha: bool) -> void: ##tween callback that updates only the tint target color of one layer
	if not _layer_active[layer]:
		return

	_layer_colors[layer] = color
	_layer_affect_alpha[layer] = affect_alpha
	_apply_tints()

func _set_tint_strength(strength: float, layer: int) -> void: ##tween callback that updates only the tint strength of one layer
	if not _layer_active[layer]:
		return

	_layer_strengths[layer] = clampf(strength, 0.0, 1.0)
	_apply_tints()

func _apply_tints() -> void: ##rebuilds the graphics sprite modulate from authored base color plus all active tint layers, then applies one shared shader overlay for non-multiplicative color pushes
	if not is_instance_valid(_root_graphics):
		return

	var final_color: Color = _base_graphics_modulate
	var overlay_state: Dictionary[StringName, Variant] = get_overlay_state()
	var overlay_color: Color = overlay_state[&"color"]
	var overlay_intensity: float = overlay_state[&"intensity"]
	for layer: int in range(LAYER_COUNT):
		if not _layer_active[layer]:
			continue

		if _layer_blend_modes[layer] == BlendMode.OVERLAY:
			continue

		var tint_color: Color = _layer_colors[layer]
		var tint_strength: float = _layer_strengths[layer]
		final_color = Color(
			lerpf(final_color.r, tint_color.r, tint_strength),
			lerpf(final_color.g, tint_color.g, tint_strength),
			lerpf(final_color.b, tint_color.b, tint_strength),
			lerpf(final_color.a, tint_color.a, tint_strength) if _layer_affect_alpha[layer] else final_color.a
		)

	_root_graphics.modulate = final_color
	_apply_shader_overlay(overlay_color, overlay_intensity)

func get_overlay_state() -> Dictionary[StringName, Variant]: ##returns the currently composed shader-overlay target so detached visuals can continue fading after the unit dies
	var overlay_color: Color = Color.WHITE
	var overlay_intensity: float = 0.0
	var has_overlay: bool = false
	for layer: int in range(LAYER_COUNT):
		if not _layer_active[layer]:
			continue

		var tint_color: Color = _layer_colors[layer]
		var tint_strength: float = _layer_strengths[layer]
		if _layer_blend_modes[layer] == BlendMode.OVERLAY:
			if not has_overlay:
				overlay_color = Color(tint_color.r, tint_color.g, tint_color.b, 1.0)
				has_overlay = true
			else:
				overlay_color = Color(
					lerpf(overlay_color.r, tint_color.r, tint_strength),
					lerpf(overlay_color.g, tint_color.g, tint_strength),
					lerpf(overlay_color.b, tint_color.b, tint_strength),
					1.0
				)
			overlay_intensity = maxf(overlay_intensity, tint_strength)
	return {
		&"color": overlay_color,
		&"intensity": overlay_intensity,
	}

func _reset_layer_state() -> void: ##initializes the fixed layer storage so all tint operations can index directly without dynamic allocation
	_layer_colors.clear()
	_layer_strengths.clear()
	_layer_affect_alpha.clear()
	_layer_blend_modes.clear()
	_layer_active.clear()
	_layer_tweens.clear()

	for _i: int in range(LAYER_COUNT):
		_layer_colors.append(Color.WHITE)
		_layer_strengths.append(0.0)
		_layer_affect_alpha.append(false)
		_layer_blend_modes.append(BlendMode.MODULATE)
		_layer_active.append(false)
		_layer_tweens.append(null)

func _apply_shader_overlay(overlay_color: Color, overlay_intensity: float) -> void: ##writes the shared overlay push target into the unit shader while preserving node modulate as the primary sampled base
	_ensure_unit_effects_material()
	if not _uses_unit_effects_shader():
		return
	_root_graphics.set_instance_shader_parameter(&"overlay_color", overlay_color)
	_root_graphics.set_instance_shader_parameter(&"overlay_intensity", overlay_intensity)

func _ensure_unit_effects_material() -> void: ##ensures units have the shared effects shader only when no bespoke material is already present
	if not is_instance_valid(_root_graphics):
		return
	if _root_graphics.material != null:
		return
	if _shared_unit_effects_material == null:
		_shared_unit_effects_material = ShaderMaterial.new()
		_shared_unit_effects_material.shader = UNIT_EFFECTS_SHADER
	_root_graphics.material = _shared_unit_effects_material

func _uses_unit_effects_shader() -> bool: ##returns whether the current root graphics material can receive overlay instance parameters
	if not (_root_graphics.material is ShaderMaterial):
		return false
	return (_root_graphics.material as ShaderMaterial).shader == UNIT_EFFECTS_SHADER

func _kill_layer_tween(layer: int) -> void: ##stops any active tween driving a layer so direct writes or replacement tweens take over immediately
	var tween: Tween = _layer_tweens[layer]
	if is_instance_valid(tween):
		tween.kill()
	_layer_tweens[layer] = null

func _assert_valid_layer(layer: int) -> void: ##crashes loudly in development if a caller uses an out-of-range tint layer
	assert(layer >= 0 and layer < LAYER_COUNT)
