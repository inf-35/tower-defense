extends Node2D
class_name RangeIndicator

enum VisualKind {
	RECT,
	LINE,
	CIRCLE,
}

class PreviewVisualState:
	var kind: int
	var payload: Dictionary[StringName, Variant]
	var signature: PackedInt64Array
	var current_alpha: float = 0.0
	var target_alpha: float = 0.0

#--- configuration ---
@export var highlight_color: Color = Color(0.94, 0.76, 0.28, 0.56)
@export var input_color: Color = Color(0.0, 0.327, 0.963, 0.541)
@export var positive_highlight_color: Color = Color(0.35, 1.0, 0.45, 0.48)
@export var negative_highlight_color: Color = Color(1.0, 0.2, 0.2, 0.48)
@export var range_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export var attack_area_color: Color = Color(1.0, 0.57, 0.57, 0.412)
@export var margin: int = 2
@export var line_width: float = 1.0
@export var preview_fade_in_duration: float = 0.12 ##time for newly requested preview visuals to ramp from transparent to full alpha
@export var preview_fade_out_duration: float = 0.1 ##time for stale preview visuals to fade away after they stop being requested

var _current_tower: Tower
var _visual_states: Dictionary[int, PreviewVisualState] = {}
var _frame_requested_visuals: Dictionary[int, bool] = {}

func _ready() -> void:
	z_index = Layers.INWORLD_UI
	z_as_relative = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func select(tower: Tower) -> void:
	_current_tower = tower
	queue_redraw()

func deselect() -> void: ##releases the active tower and lets any remaining cached preview visuals fade out naturally
	_current_tower = null
	for visual_state: PreviewVisualState in _visual_states.values():
		visual_state.target_alpha = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if _current_tower != null and not is_instance_valid(_current_tower):
		deselect()
	if _advance_visual_fades(delta):
		queue_redraw()
	elif is_instance_valid(_current_tower):
		queue_redraw()

func _draw() -> void:
	_frame_requested_visuals.clear()
	if is_instance_valid(_current_tower) and is_instance_valid(_current_tower.behavior):
		_current_tower.behavior.draw_visuals(self)
	_finalize_frame_requests()
	_draw_visual_states()

func preview_cell(cell: Vector2i, color: Color, width: float = 1.0) -> void: ##records one cell outline as a retained preview visual that can fade in and out across mouse movement
	var cell_size: float = Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2.ONE * cell_size * 0.5
	var rect := Rect2(Island.cell_to_position(cell) - half_size, Vector2.ONE * cell_size)
	preview_rect(rect, color, false, width)

func preview_rect(rect: Rect2, color: Color, filled: bool = false, width: float = 1.0) -> void: ##records one retained rectangle visual keyed by its geometry so the same tile can animate smoothly across preview updates
	var payload: Dictionary[StringName, Variant] = {
		&"rect": rect,
		&"color": color,
		&"filled": filled,
		&"width": width,
	}
	_record_visual(
		VisualKind.RECT,
		payload
	)

func preview_line(from: Vector2, to: Vector2, color: Color, width: float = 1.0, antialiased: bool = false) -> void: ##records one retained line visual keyed by its endpoints so preview links can fade rather than pop
	var payload: Dictionary[StringName, Variant] = {
		&"from": from,
		&"to": to,
		&"color": color,
		&"width": width,
		&"antialiased": antialiased,
	}
	_record_visual(
		VisualKind.LINE,
		payload
	)

func preview_circle(center: Vector2, radius: float, color: Color, filled: bool = false, width: float = 1.0, antialiased: bool = false) -> void: ##records one retained circle visual so range rings use the same fade model as tile highlights
	var payload: Dictionary[StringName, Variant] = {
		&"center": center,
		&"radius": radius,
		&"color": color,
		&"filled": filled,
		&"width": width,
		&"antialiased": antialiased,
	}
	_record_visual(
		VisualKind.CIRCLE,
		payload
	)

func draw_cell(cell: Vector2i, color: Color) -> void:
	preview_cell(cell, color, 1.0)

func _record_visual(kind: int, payload: Dictionary[StringName, Variant]) -> void: ##upserts one frame-requested visual while preserving its live alpha state across redraws
	var signature: PackedInt64Array = _encode_visual_signature(kind, payload)
	var key: int = _resolve_visual_key(signature)
	_frame_requested_visuals[key] = true
	if not _visual_states.has(key):
		var visual_state := PreviewVisualState.new()
		visual_state.kind = kind
		visual_state.payload = payload
		visual_state.signature = signature
		visual_state.target_alpha = (payload[&"color"] as Color).a
		_visual_states[key] = visual_state
		return

	var visual_state: PreviewVisualState = _visual_states[key]
	visual_state.kind = kind
	visual_state.payload = payload
	visual_state.signature = signature
	visual_state.target_alpha = (payload[&"color"] as Color).a

func _finalize_frame_requests() -> void: ##marks every visual not requested this frame for fade-out without immediately deleting it
	for key: int in _visual_states:
		if _frame_requested_visuals.has(key):
			continue
		_visual_states[key].target_alpha = 0.0

func _advance_visual_fades(delta: float) -> bool: ##advances all preview alpha tweens in one place and removes fully faded visuals from the cache
	var changed: bool = false
	var fade_in_step: float = delta / maxf(preview_fade_in_duration, 0.001)
	var fade_out_step: float = delta / maxf(preview_fade_out_duration, 0.001)
	var keys_to_remove: Array[int] = []
	for key: int in _visual_states:
		var visual_state: PreviewVisualState = _visual_states[key]
		var step: float = fade_in_step if visual_state.current_alpha < visual_state.target_alpha else fade_out_step
		var next_alpha: float = move_toward(visual_state.current_alpha, visual_state.target_alpha, step)
		if not is_equal_approx(next_alpha, visual_state.current_alpha):
			visual_state.current_alpha = next_alpha
			changed = true
		if is_zero_approx(visual_state.current_alpha) and is_zero_approx(visual_state.target_alpha):
			keys_to_remove.append(key)

	for key: int in keys_to_remove:
		_visual_states.erase(key)
		changed = true

	return changed or not _visual_states.is_empty()

func _draw_visual_states() -> void: ##renders the retained visual cache using each visual state's animated alpha instead of the raw authored alpha
	for visual_state: PreviewVisualState in _visual_states.values():
		if visual_state.current_alpha <= 0.0:
			continue

		var color: Color = visual_state.payload[&"color"]
		color.a = visual_state.current_alpha
		match visual_state.kind:
			VisualKind.RECT:
				draw_rect(
					visual_state.payload[&"rect"],
					color,
					visual_state.payload[&"filled"],
					visual_state.payload[&"width"]
				)
			VisualKind.LINE:
				draw_line(
					visual_state.payload[&"from"],
					visual_state.payload[&"to"],
					color,
					visual_state.payload[&"width"],
					visual_state.payload[&"antialiased"]
				)
			VisualKind.CIRCLE:
				draw_circle(
					visual_state.payload[&"center"],
					visual_state.payload[&"radius"],
					color,
					visual_state.payload[&"filled"],
					visual_state.payload[&"width"],
					visual_state.payload[&"antialiased"]
				)

func _resolve_visual_key(signature: PackedInt64Array) -> int: ##maps one encoded geometry signature to a stable integer key while probing around rare hash collisions
	var key: int = _hash_signature(signature)
	while _visual_states.has(key) and _visual_states[key].signature != signature:
		key += 1
	return key

func _encode_visual_signature(kind: int, payload: Dictionary[StringName, Variant]) -> PackedInt64Array: ##encodes all retained preview geometry through one integer signature scheme rather than per-shape string formatting
	match kind:
		VisualKind.RECT:
			var rect: Rect2 = payload[&"rect"]
			return PackedInt64Array([
				kind,
				_quantize_float(rect.position.x),
				_quantize_float(rect.position.y),
				_quantize_float(rect.size.x),
				_quantize_float(rect.size.y),
				int(payload[&"filled"]),
				_quantize_float(payload[&"width"]),
			])
		VisualKind.LINE:
			var from: Vector2 = payload[&"from"]
			var to: Vector2 = payload[&"to"]
			return PackedInt64Array([
				kind,
				_quantize_float(from.x),
				_quantize_float(from.y),
				_quantize_float(to.x),
				_quantize_float(to.y),
				_quantize_float(payload[&"width"]),
				int(payload[&"antialiased"]),
			])
		VisualKind.CIRCLE:
			var center: Vector2 = payload[&"center"]
			return PackedInt64Array([
				kind,
				_quantize_float(center.x),
				_quantize_float(center.y),
				_quantize_float(payload[&"radius"]),
				int(payload[&"filled"]),
				_quantize_float(payload[&"width"]),
				int(payload[&"antialiased"]),
			])
	return PackedInt64Array([kind])

func _hash_signature(signature: PackedInt64Array) -> int: ##folds one integer signature into a compact dictionary key
	var hash_value: int = 1469598103934665603
	for value: int in signature:
		hash_value = int((hash_value ^ value) * 1099511628211)
	return hash_value

func _quantize_float(value: float) -> int: ##normalizes geometry floats into stable integer slots so the same preview geometry reuses one retained key
	return roundi(value * 100.0)
