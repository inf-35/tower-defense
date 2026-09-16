extends Node2D
class_name FloatingTextManager

class PendingDamageValue extends RefCounted:
	var owner_ref: WeakRef
	var fallback_position: Vector2 = Vector2.ZERO
	var total: float = 0.0
	var color: Color = Color.TRANSPARENT
	var scale_mod: float = 1.0
	var ignore_pause: bool = false
	var elapsed: float = 0.0
	var quiet_elapsed: float = 0.0

class DamageTextStyle extends RefCounted:
	var text: String = ""
	var color: Color = Color.TRANSPARENT
	var scale_mult: float = 1.0
	var lifetime: float = 0.5
	var z_index_offset: int = 0

#--- configuration ---
@export var text_scene: PackedScene
@export var initial_pool_size: int = 20

@export_group("Damage Presentation")
@export var damage_scale_minimum: float = 1.0 ##smallest automatic damage-number scale before caller scale modifiers are applied
@export var damage_scale_log_base: float = 2.0 ##logarithm base for damage-number size growth
@export var damage_scale_per_step: float = 0.12 ##scale added for each logarithmic step above 1 damage
@export var damage_large_color: Color = Color(0.23, 0.52, 0.062, 1.0) ##fill color for damage values of 8 or more
@export var damage_huge_color: Color = Color(0.141, 0.365, 0.64, 1.0) ##fill color for damage values of 16 or more
@export var damage_massive_color: Color = Color(0.618, 0.286, 0.84, 1.0) ##fill color for damage values of 30 or more
@export var damage_critical_color: Color = Color(0.82, 0.601, 0.0, 1.0) ##fill color for damage values of 100 or more

@export_group("Damage Coalescing")
@export var damage_coalescing_global_threshold: int = 24 ##global damage labels allowed per rate window before subsequent labels coalesce
@export var damage_coalescing_rate_window_seconds: float = 0.2 ##realtime window used to detect screen-wide damage label spam
@export var damage_coalescing_flushes_per_frame: int = 24 ##maximum delayed damage labels materialized in one rendered frame

@export_group("Physics Defaults")
@export var default_velocity_min: Vector2 = Vector2(-2, -5)
@export var default_velocity_max: Vector2 = Vector2(2, -8)
@export var default_gravity: float = 10.0
@export var default_lifetime: float = 0.5

const DAMAGE_AGGREGATION_QUIET_SECONDS: float = 0.16
const DAMAGE_AGGREGATION_MAX_SECONDS: float = 0.35
const DAMAGE_MERGED_MIN_REMAINING_SECONDS: float = 0.28

#--- state ---
var _pool: Array[FloatingText] = []
var _active_count: int = 0
var _pending_damage_values: Dictionary[int, PendingDamageValue] = {}
var _pending_damage_value_order: Array[int] = []
var _damage_rate_window_start_msec: int = 0
var _damage_rate_event_count: int = 0
var _active_damage_texts: Dictionary[int, FloatingText] = {}
var _active_damage_totals: Dictionary[int, float] = {}
var _damage_text_owner_by_text_id: Dictionary[int, int] = {}

func _ready() -> void:
	UI.floating_text_manager = self
	set_process(false)

	#pre-populate
	if text_scene:
		for i in range(initial_pool_size):
			_pool.append(_create_new_text())

#--- public api ---

func show_value(value: float, world_pos: Vector2, color: Color = Color.WHITE, scale_mod: float = 1.0, ignore_pause: bool = false) -> void:
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_value_requests")
	if DebugAssistant.disable_floating_text:
		return
	var str_val = str(snappedf(value, 0.1))
	var final_color = color
	var scale_mult = scale_mod

	_spawn_text(str_val, world_pos, final_color, scale_mult, 1.0, 0.0, 0.3, ignore_pause)

func show_damage_value(value: float, owner: Node2D, color: Color = Color.TRANSPARENT, scale_mod: float = 1.0, ignore_pause: bool = false) -> void: ##coalesces damage labels per unit over a short realtime window
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_damage_requests")
	if DebugAssistant.disable_floating_text:
		return
	if not is_instance_valid(owner):
		return

	var owner_id: int = owner.get_instance_id()
	if not _should_coalesce_damage_globally():
		_spawn_damage_text_immediately(value, owner.global_position, color, scale_mod, ignore_pause)
		return
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"damage_text_coalesced_requests")

	var pending_value: PendingDamageValue = _pending_damage_values.get(owner_id, null)
	if pending_value == null:
		pending_value = PendingDamageValue.new()
		pending_value.owner_ref = weakref(owner)
		pending_value.fallback_position = owner.global_position
		pending_value.color = color
		pending_value.scale_mod = scale_mod
		pending_value.ignore_pause = ignore_pause
		_pending_damage_values[owner_id] = pending_value
		_pending_damage_value_order.append(owner_id)

	pending_value.total += value
	pending_value.fallback_position = owner.global_position
	pending_value.scale_mod = maxf(pending_value.scale_mod, scale_mod)
	pending_value.ignore_pause = pending_value.ignore_pause or ignore_pause
	pending_value.quiet_elapsed = 0.0
	set_process(true)

func _should_coalesce_damage_globally() -> bool: ##returns true once screen-wide damage labels exceed the configured realtime rate threshold
	var now_msec: int = Time.get_ticks_msec()
	var window_msec: int = maxi(1, roundi(maxf(damage_coalescing_rate_window_seconds, 0.001) * 1000.0))
	if _damage_rate_window_start_msec <= 0 or now_msec - _damage_rate_window_start_msec > window_msec:
		_damage_rate_window_start_msec = now_msec
		_damage_rate_event_count = 0

	_damage_rate_event_count += 1
	return _damage_rate_event_count > maxi(damage_coalescing_global_threshold, 0)

func _spawn_damage_text_immediately(value: float, world_pos: Vector2, color: Color, scale_mod: float, ignore_pause: bool) -> void: ##keeps low-volume damage readable by bypassing burst coalescing
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"damage_text_immediate_spawns")
	var style: DamageTextStyle = _build_damage_text_style(value, color, scale_mod)
	var text: FloatingText = _spawn_text(style.text, world_pos, style.color, style.scale_mult, 1.0, 0.0, 0.3, ignore_pause, style.lifetime)
	if is_instance_valid(text):
		text.set_z_index_offset(style.z_index_offset)

func show_text(text: String, world_pos: Vector2, color: Color, ignore_pause: bool = false) -> void:
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_text_requests")
	if DebugAssistant.disable_floating_text:
		return
	_spawn_text(text, world_pos, color, 1.0, 1.0, 0.0, 0.3, ignore_pause)

func show_text_with_profile(
	text: String,
	world_pos: Vector2,
	color: Color,
	peak_alpha: float = 1.0,
	ramp_up_ratio: float = 0.0,
	fade_out_ratio: float = 0.3,
	scale_mod: float = 1.0,
	ignore_pause: bool = false,
	custom_time: float = -1.0
) -> void:
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_text_requests")
	if DebugAssistant.disable_floating_text:
		return
	_spawn_text(text, world_pos, color, scale_mod, peak_alpha, ramp_up_ratio, fade_out_ratio, ignore_pause, custom_time)

func show_icon(icon: Texture2D, world_pos: Vector2, scale_mod: float = 1.0, ignore_pause: bool = false, custom_time: float = -1.0) -> void:
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_icon_requests")
	if DebugAssistant.disable_floating_text:
		return
	if not icon: return

	var instance: FloatingText = _borrow_text()

	_active_count += 1

	#float up
	var vel: Vector2 = Vector2(0, -7.0)
	instance.scale = Vector2(0.06, 0.06) * scale_mod

	var lifetime = custom_time if custom_time > 0.0 else (0.5 if Run.phases.current_phase == Run.phases.GamePhase.COMBAT_WAVE else 1.2)
	var color: Color = Color(1,1,1,0.5) if Run.phases.current_phase == Run.phases.GamePhase.COMBAT_WAVE else Color.WHITE
	instance.setup_icon(icon, world_pos, color, vel, 0.0, lifetime, self, ignore_pause) #0 gravity
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_spawned")

func _process(delta: float) -> void: ##flushes aggregated damage labels on real time once bursts settle or hit the max hold time
	if _pending_damage_values.is_empty():
		set_process(false)
		return

	var ready_owner_ids: Array[int] = []
	for owner_id: int in _pending_damage_value_order:
		var pending_value: PendingDamageValue = _pending_damage_values.get(owner_id, null)
		if pending_value == null:
			ready_owner_ids.append(owner_id)
			continue

		pending_value.elapsed += delta
		pending_value.quiet_elapsed += delta
		if pending_value.quiet_elapsed >= DAMAGE_AGGREGATION_QUIET_SECONDS or pending_value.elapsed >= DAMAGE_AGGREGATION_MAX_SECONDS:
			ready_owner_ids.append(owner_id)
			if ready_owner_ids.size() >= maxi(damage_coalescing_flushes_per_frame, 1):
				break

	for owner_id: int in ready_owner_ids:
		_flush_damage_value(owner_id)

	if _pending_damage_values.is_empty():
		set_process(false)

func _spawn_text(
	txt: String,
	pos: Vector2,
	col: Color,
	scale_mod: float,
	peak_alpha: float = 1.0,
	ramp_up_ratio: float = 0.0,
	fade_out_ratio: float = 0.3,
	ignore_pause: bool = false,
	lifetime_override: float = -1.0
) -> FloatingText:
	var instance: FloatingText = _borrow_text()

	_active_count += 1

	var vel: Vector2 = Vector2(
		randf_range(default_velocity_min.x, default_velocity_max.x),
		randf_range(default_velocity_min.y, default_velocity_max.y)
	) * scale_mod

	instance.scale = Vector2(0.06, 0.06) * scale_mod

	var lifetime: float = lifetime_override if lifetime_override > 0.0 else default_lifetime
	instance.setup(txt, pos, col, vel, default_gravity, lifetime, self, peak_alpha, ramp_up_ratio, fade_out_ratio, ignore_pause)
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"floating_text_spawned")
	return instance

func _flush_damage_value(owner_id: int) -> void: ##emits one floating number for a unit's burst of damage without changing the damage events themselves
	var pending_value: PendingDamageValue = _pending_damage_values.get(owner_id, null)
	_pending_damage_values.erase(owner_id)
	_pending_damage_value_order.erase(owner_id)
	if pending_value == null:
		return
	if DebugAssistant.disable_floating_text:
		return

	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"damage_text_flushes")
	var display_position: Vector2 = pending_value.fallback_position
	if is_instance_valid(pending_value.owner_ref):
		var owner: Node2D = pending_value.owner_ref.get_ref() as Node2D
		if is_instance_valid(owner):
			display_position = owner.global_position

	_merge_or_spawn_damage_text(owner_id, pending_value.total, display_position, pending_value.color, pending_value.scale_mod, pending_value.ignore_pause)

func _merge_or_spawn_damage_text(owner_id: int, value: float, pos: Vector2, color: Color, scale_mod: float, ignore_pause: bool) -> void: ##folds repeated damage for one unit into its existing visible label where possible
	var active_text: FloatingText = _active_damage_texts.get(owner_id, null)
	if is_instance_valid(active_text) and active_text.visible and active_text.is_inside_tree():
		var merged_total: float = _active_damage_totals.get(owner_id, 0.0) + value
		_active_damage_totals[owner_id] = merged_total
		var merged_style: DamageTextStyle = _build_damage_text_style(merged_total, color, scale_mod)
		active_text.merge_text(
			merged_style.text,
			pos,
			merged_style.color,
			Vector2(0.06, 0.06) * merged_style.scale_mult,
			merged_style.z_index_offset,
			merged_style.lifetime,
			DAMAGE_MERGED_MIN_REMAINING_SECONDS
		)
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"damage_text_merges")
		return

	_active_damage_texts.erase(owner_id)
	_active_damage_totals.erase(owner_id)
	var style: DamageTextStyle = _build_damage_text_style(value, color, scale_mod)
	var new_text: FloatingText = _spawn_text(style.text, pos, style.color, style.scale_mult, 1.0, 0.0, 0.3, ignore_pause, style.lifetime)
	if not is_instance_valid(new_text):
		return

	new_text.set_z_index_offset(style.z_index_offset)
	_active_damage_texts[owner_id] = new_text
	_active_damage_totals[owner_id] = value
	_damage_text_owner_by_text_id[new_text.get_instance_id()] = owner_id

func _build_damage_text_style(value: float, fallback_color: Color, caller_scale_mod: float) -> DamageTextStyle: ##formats one damage number and selects its color, z, and logarithmic scale tier
	var style := DamageTextStyle.new()
	var damage_scale: float = _get_damage_scale(value)
	style.text = _format_damage_text(value)
	style.color = _get_damage_fill_color(value, fallback_color)
	style.scale_mult = caller_scale_mod * damage_scale
	style.lifetime = default_lifetime * style.scale_mult
	style.z_index_offset = _get_damage_z_index_offset(value)
	return style

func _format_damage_text(value: float) -> String: ##rounds damage as before and marks extreme hits with an exclamation point
	var text_value: String = str(snappedf(value, 0.1))
	if value >= 100.0:
		text_value += "!"
	return text_value

func _get_damage_scale(value: float) -> float: ##uses logarithmic growth so large hits read louder without dwarfing the screen
	var safe_value: float = maxf(value, 1.0)
	var safe_base: float = maxf(damage_scale_log_base, 1.001)
	var log_steps: float = log(safe_value) / log(safe_base)
	return maxf(damage_scale_minimum, damage_scale_minimum + (log_steps * damage_scale_per_step))

func _get_damage_fill_color(value: float, fallback_color: Color) -> Color: ##returns the highest crossed damage-tier fill color, leaving small damage on the caller's color
	if value >= 100.0:
		return damage_critical_color
	if value >= 30.0:
		return damage_massive_color
	if value >= 16.0:
		return damage_huge_color
	if value >= 8.0:
		return damage_large_color
	return fallback_color

func _get_damage_z_index_offset(value: float) -> int: ##raises larger hits above ordinary damage labels while staying within the floating text parent
	if value >= 100.0:
		return 4
	if value >= 30.0:
		return 3
	if value >= 16.0:
		return 2
	if value >= 8.0:
		return 1
	return 0

func _borrow_text() -> FloatingText: ##returns one reusable floating text, expanding only when every pooled label is active
	while not _pool.is_empty():
		var text: Variant = _pool.pop_back()
		if is_instance_valid(text):
			return text as FloatingText

	return _create_new_text()

func _create_new_text() -> FloatingText:
	var t = text_scene.instantiate() as FloatingText
	t.visible = false
	t.set_process(false)
	add_child(t)
	return t

func return_text(text: FloatingText) -> void:
	if not is_instance_valid(text):
		return
	if _pool.has(text):
		return

	_clear_damage_text_tracking(text)
	_pool.append(text)
	_active_count = maxi(_active_count - 1, 0)

func _clear_damage_text_tracking(text: FloatingText) -> void: ##removes owner bookkeeping when a coalesced damage label returns to the pool
	if not is_instance_valid(text):
		return

	var text_id: int = text.get_instance_id()
	if not _damage_text_owner_by_text_id.has(text_id):
		return

	var owner_id: int = _damage_text_owner_by_text_id[text_id]
	_damage_text_owner_by_text_id.erase(text_id)
	if _active_damage_texts.get(owner_id, null) == text:
		_active_damage_texts.erase(owner_id)
		_active_damage_totals.erase(owner_id)
