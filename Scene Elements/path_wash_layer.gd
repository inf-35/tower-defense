extends Node2D
class_name PathWashLayer

@export var wash_color: Color = Color(0.98, 0.94, 0.82, 0.48) ##cream pigment laid beneath ordinary enemy routes
@export_range(1.0, 20.0, 0.1) var wash_width: float = 7.4 ##base width of the route wash in world units
@export_range(0.0, 5.0, 0.1) var edge_variation: float = 0.55 ##deterministic lateral variation used to soften geometric path edges
@export_range(0.0, 5.0, 0.1) var corner_radius: float = 2.8 ##distance from a grid corner at which the rounded turn begins
@export_range(1, 8, 1) var corner_steps: int = 4 ##quadratic samples used to round each route corner
@export_range(0.01, 2.0, 0.01) var fade_in_duration: float = 0.16 ##real-time duration for newly selected routes to appear
@export_range(0.0, 1.0, 0.01) var removed_route_hold: float = 0.08 ##brief persistence before an obsolete route begins fading
@export_range(0.01, 2.0, 0.01) var fade_out_duration: float = 0.28 ##real-time duration for obsolete routes to disappear

class WashState extends RefCounted:
	var signature: int
	var points: PackedVector2Array
	var alpha: float = 0.0
	var target_alpha: float = 1.0
	var hold_remaining: float = 0.0
	var opacity_scale: float = 1.0

	func _init(path_signature: int, path_points: PackedVector2Array) -> void:
		signature = path_signature
		points = path_points

var _states: Dictionary[int, WashState] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func configure_environment(profile: EnvironmentProfile) -> void: ##applies the active environment's route pigment without changing shared route geometry or transitions
	if profile == null:
		return
	wash_color = profile.path_wash_color
	queue_redraw()

func set_paths(paths: Array[PackedVector2Array], route_opacity_scale: float = 1.0) -> void: ##crossfades the presentation cache toward the supplied ordinary-enemy route geometry and shared density scale
	var active_signatures: Dictionary[int, bool] = {}
	for path_points: PackedVector2Array in paths:
		if path_points.size() < 2:
			continue

		var signature: int = hash(path_points)
		active_signatures[signature] = true
		var state: WashState = _states.get(signature)
		if state == null:
			state = WashState.new(signature, _prepare_path(path_points))
			_states[signature] = state
		state.target_alpha = 1.0
		state.hold_remaining = 0.0
		state.opacity_scale = route_opacity_scale

	for signature: int in _states:
		if active_signatures.has(signature):
			continue
		var stale_state: WashState = _states[signature]
		if stale_state.target_alpha > 0.0:
			stale_state.target_alpha = 0.0
			stale_state.hold_remaining = removed_route_hold

	set_process(true)
	queue_redraw()

func _process(delta: float) -> void: ##advances route crossfades independently of pause state or combat speed
	var changed: bool = false
	var removals: Array[int] = []
	for signature: int in _states:
		var state: WashState = _states[signature]
		if state.target_alpha > 0.0:
			var next_alpha: float = move_toward(state.alpha, 1.0, delta / fade_in_duration)
			changed = changed or not is_equal_approx(next_alpha, state.alpha)
			state.alpha = next_alpha
			continue

		if state.hold_remaining > 0.0:
			state.hold_remaining = maxf(0.0, state.hold_remaining - delta)
			changed = true
			continue

		var next_alpha: float = move_toward(state.alpha, 0.0, delta / fade_out_duration)
		changed = changed or not is_equal_approx(next_alpha, state.alpha)
		state.alpha = next_alpha
		if state.alpha <= 0.0:
			removals.append(signature)

	for signature: int in removals:
		_states.erase(signature)

	if changed or not removals.is_empty():
		queue_redraw()
	if _is_stable():
		set_process(false)

func _draw() -> void: ##layers stable offset strokes so the route reads as one mottled watercolor band
	for state: WashState in _states.values():
		if state.alpha <= 0.0:
			continue
		_draw_wash_pass(state, 0, wash_width * 1.12, 0.20)
		_draw_wash_pass(state, 1, wash_width * 0.94, 0.32)
		_draw_wash_pass(state, 2, wash_width * 0.72, 0.24)

func _draw_wash_pass(state: WashState, pass_index: int, width: float, opacity: float) -> void: ##draws one deterministic translucent pigment pass, including rounded route ends
	var points: PackedVector2Array = _offset_path(state.points, state.signature, pass_index)
	var color: Color = wash_color.lerp(Color(1.0, 1.0, 1.0, wash_color.a), float(pass_index) * 0.08)
	color.a *= state.alpha * state.opacity_scale * opacity
	draw_polyline(points, color, width, true)
	draw_circle(points[0], width * 0.5, color, true, -1.0, true)
	draw_circle(points[points.size() - 1], width * 0.5, color, true, -1.0, true)

func _prepare_path(points: PackedVector2Array) -> PackedVector2Array: ##rounds grid corners and resamples the route so edge variation changes smoothly along its length
	var rounded: PackedVector2Array = _round_corners(points)
	return _resample_path(rounded, 2.0)

func _round_corners(points: PackedVector2Array) -> PackedVector2Array: ##replaces each hard grid turn with a short quadratic curve
	if points.size() < 3:
		return points

	var result := PackedVector2Array([points[0]])
	for index: int in range(1, points.size() - 1):
		var previous: Vector2 = points[index - 1]
		var corner: Vector2 = points[index]
		var following: Vector2 = points[index + 1]
		var incoming: Vector2 = (corner - previous).normalized()
		var outgoing: Vector2 = (following - corner).normalized()
		if incoming.dot(outgoing) > 0.999:
			result.append(corner)
			continue

		var radius: float = minf(corner_radius, minf(previous.distance_to(corner), corner.distance_to(following)) * 0.45)
		var entry: Vector2 = corner - incoming * radius
		var exit: Vector2 = corner + outgoing * radius
		result.append(entry)
		for step: int in range(1, corner_steps + 1):
			var weight: float = float(step) / float(corner_steps)
			var inverse: float = 1.0 - weight
			result.append(inverse * inverse * entry + 2.0 * inverse * weight * corner + weight * weight * exit)

	result.append(points[points.size() - 1])
	return result

func _resample_path(points: PackedVector2Array, spacing: float) -> PackedVector2Array: ##inserts evenly spaced samples so the watercolor wobble is continuous rather than cell-shaped
	var result := PackedVector2Array([points[0]])
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[index + 1]
		var distance: float = start.distance_to(finish)
		var steps: int = maxi(1, ceili(distance / spacing))
		for step: int in range(1, steps + 1):
			result.append(start.lerp(finish, float(step) / float(steps)))
	return result

func _offset_path(points: PackedVector2Array, signature: int, pass_index: int) -> PackedVector2Array: ##adds low-frequency deterministic edge drift without producing frame-to-frame shimmer
	var result := PackedVector2Array()
	var seed_phase: float = float(abs(signature) % 2048) * 0.013 + float(pass_index) * 1.91
	for index: int in points.size():
		var previous: Vector2 = points[maxi(0, index - 1)]
		var following: Vector2 = points[mini(points.size() - 1, index + 1)]
		var tangent: Vector2 = (following - previous).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var phase: float = seed_phase + float(index) * 0.47
		var drift: float = sin(phase) + sin(phase * 0.43 + 1.7) * 0.42
		var end_fade: float = sin(PI * float(index) / float(points.size() - 1))
		result.append(points[index] + normal * drift * edge_variation * end_fade)
	return result

func _is_stable() -> bool: ##sleeps the presentation node once every live route is fully visible and no stale route remains
	for state: WashState in _states.values():
		if state.target_alpha <= 0.0 or not is_equal_approx(state.alpha, 1.0):
			return false
	return true
