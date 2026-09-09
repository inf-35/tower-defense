extends Node
#VFXManager. Bypasses the scene tree and calls the renderingserver directly
const PROJECTILE_TINT_CYCLE_PROPORTION: float = 0.4 ##per-tint blend duration expressed as a proportion of the projectile lifetime basis
const MIN_PROJECTILE_TINT_CYCLE_TIME: float = 0.12 ##lower clamp for per-tint blend duration so short-lived projectiles do not flicker through colors too quickly
const MAX_PROJECTILE_TINT_CYCLE_TIME: float = 0.6 ##upper clamp for per-tint blend duration so long-lived projectiles still cycle visibly before impact
const PROJECTILE_WHITE_PUSH: float = 0.5##fraction of each projectile tint blended toward white so shots read crisply against terrain


class SceneTintState extends RefCounted:
	var canvas_item: CanvasItem
	var base_modulate: Color = Color.WHITE
	var projectile_tints: Array[Color] = []
	var white_push_enabled: bool = false
	var age: float = 0.0
	var lifetime: float = 0.0
	var tint_cycle_lifetime: float = -1.0

var _active_vfx: Array[VFXInstance] = []
var _active_scene_tints: Array[SceneTintState] = []
var _projectile_trail_canvas_item: RID
#a flat array allows for optimal memory access

func _ready() -> void: ##registers the render-server draw hook while leaving per-frame simulation asleep until effects exist
	#we draw our effects ourselves during the frame_post_draw signal.
	set_process(false)
	_projectile_trail_canvas_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_projectile_trail_canvas_item, get_viewport().world_2d.canvas)
	RenderingServer.canvas_item_set_z_index(_projectile_trail_canvas_item, Layers.ALLIED_PROJECTILES + 1)
	RenderingServer.frame_post_draw.connect(_draw_vfx)

func _process(_d: float) -> void: ##advances procedural vfx and scene tint cycles only while one of those systems has live work
	var delta: float = Clock.game_delta
	if _active_vfx.is_empty() and _active_scene_tints.is_empty():
		return

	if delta == 0.0: #the game is paused, probably
		return

	var vfx_to_remove: Array[VFXInstance] = []
	#--- update the state of all active effects ---
	for vfx : VFXInstance in _active_vfx:
		#update lifetime
		vfx.age += delta
		if vfx.age >= vfx.lifetime and vfx.lifetime > 0.0:
			vfx.delete = true
		if vfx.delete:
			vfx_to_remove.append(vfx)
			continue
		vfx.position -= Vector2(0, vfx.vertical * CombatManager.PSEUDOVERTICAL_RATIO) #remove pseudovertical offset
		#update position and rotation
		vfx.position += vfx.velocity * delta
		vfx.vertical += vfx.vertical_velocity * delta
		vfx.position += Vector2(0, vfx.vertical * CombatManager.PSEUDOVERTICAL_RATIO)
		if vfx.arcing:
			vfx.vertical_velocity += vfx.vertical_gravity * delta
		if _is_projectile_trail_enabled(vfx):
			_record_projectile_trail_point(vfx)

		match vfx.vfx_info.rotation_mode:
			VFXInfo.RotationMode.FACE_VELOCITY when not vfx.velocity.is_zero_approx():
				vfx.rotation = (vfx.velocity + Vector2(0, vfx.vertical_velocity * CombatManager.PSEUDOVERTICAL_RATIO)).angle()
			VFXInfo.RotationMode.SPIN:
				vfx.rotation += vfx.vfx_info.spin_speed * delta

	for vfx : VFXInstance in vfx_to_remove: #deferred cleanup
		_cleanup_vfx(vfx)

	var scene_tints_to_remove: Array[SceneTintState] = []
	for scene_tint: SceneTintState in _active_scene_tints:
		if not is_instance_valid(scene_tint.canvas_item):
			scene_tints_to_remove.append(scene_tint)
			continue

		scene_tint.age += delta
		var current_modulate: Color = scene_tint.base_modulate * _get_projectile_tint(scene_tint.projectile_tints, scene_tint.age, scene_tint.tint_cycle_lifetime)
		if scene_tint.white_push_enabled:
			current_modulate = _push_projectile_white(current_modulate)
		scene_tint.canvas_item.modulate = current_modulate

		if scene_tint.lifetime > 0.0 and scene_tint.age >= scene_tint.lifetime:
			scene_tints_to_remove.append(scene_tint)

	for scene_tint: SceneTintState in scene_tints_to_remove:
		_active_scene_tints.erase(scene_tint)

	if _active_vfx.is_empty() and _active_scene_tints.is_empty():
		set_process(false)

func _draw_vfx() -> void: ##redraws all procedural vfx plus one shared projectile-trail canvas item on the render server
	if DebugAssistant.disable_vfx_visuals:
		_clear_active_vfx_draws()
		return

	_draw_projectile_trails()

	for vfx : VFXInstance in _active_vfx:
		if vfx.is_projectile and DebugAssistant.disable_projectile_visuals:
			_clear_vfx_draw(vfx)
			continue

		var info: VFXInfo = vfx.vfx_info
		var normalized_lifetime: float = 0.0
		if vfx.lifetime > 0.0:
			normalized_lifetime = clampf(vfx.age / vfx.lifetime, 0.0, 1.0)
		var canvas_item_rid: RID = vfx.canvas_item

		#--- calculate common properties ---
		var current_scale_val = 1.0 if not info.scale_over_lifetime else info.scale_over_lifetime.sample(normalized_lifetime)
		current_scale_val *= info.scale
		var current_color = Color.WHITE if not info.color_over_lifetime else info.color_over_lifetime.sample(normalized_lifetime)
		current_color *= _get_projectile_tint(vfx.projectile_tints, vfx.age, vfx.projectile_tint_lifetime)
		if vfx.is_projectile:
			current_color = _push_projectile_white(current_color)
		var transform: Transform2D = Transform2D(vfx.rotation, Vector2.ZERO).scaled(Vector2(current_scale_val, current_scale_val))
		transform = transform.translated(vfx.position)

		#critical: we must clear the canvas item before drawing the new frame.
		RenderingServer.canvas_item_clear(canvas_item_rid)

		#apply the transform and color globally for this item
		RenderingServer.canvas_item_set_transform(canvas_item_rid, transform)
		RenderingServer.canvas_item_set_modulate(canvas_item_rid, current_color)

		#--- call the correct renderingserver function based on type ---
		match info.vfx_type:
			VFXInfo.VFXType.TEXTURE:
				if not is_instance_valid(info.texture):
					continue #abort
				RenderingServer.canvas_item_set_transform(
					canvas_item_rid,
					Transform2D(vfx.rotation, Vector2.ZERO).scaled(Vector2(current_scale_val, current_scale_val)).translated(vfx.position)
				)

				var frame := int(vfx.age * info.fps) % (info.h_frames * info.v_frames)
				var fx: int = frame % info.h_frames
				@warning_ignore_start("integer_division")
				var fy: int = frame / info.h_frames
				var region_w = info.texture.get_width() / info.h_frames
				var region_h = info.texture.get_height() / info.v_frames
				var region: Rect2 = Rect2(fx * region_w, fy * region_h, region_w, region_h)
				var draw_rect: Rect2 = Rect2(-region.size * 0.5, region.size)
				RenderingServer.canvas_item_add_texture_rect_region(canvas_item_rid, draw_rect, info.texture.get_rid(), region)

			VFXInfo.VFXType.CIRCLE:
				var radius: float = vfx.scale.x * info.radius * current_scale_val
				#for primitives, position is handled by the transform, not the primitive's offset.)
				RenderingServer.canvas_item_add_circle(canvas_item_rid, Vector2.ZERO, radius, current_color)

			VFXInfo.VFXType.RECTANGLE:
				var size: Vector2 = vfx.scale * info.size * current_scale_val
				var rect: Rect2 = Rect2(-size / 2.0, size)
				RenderingServer.canvas_item_set_transform(canvas_item_rid, transform)
				if info.filled:
					RenderingServer.canvas_item_add_rect(canvas_item_rid, rect, current_color)
				else:
					var corners: PackedVector2Array = [
						rect.position,
						Vector2(rect.position.x + rect.size.x, rect.position.y),
						rect.position + rect.size,
						Vector2(rect.position.x, rect.position.y + rect.size.y)
					]
					RenderingServer.canvas_item_add_polyline(canvas_item_rid, corners, current_color, info.primitive_width)

func _draw_projectile_trails() -> void: ##draws smoothed tapered projectile ribbons without allocating per-projectile nodes
	RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)
	if DebugAssistant.disable_projectile_trails or DebugAssistant.disable_projectile_visuals:
		return

	for vfx: VFXInstance in _active_vfx:
		if not _is_projectile_trail_enabled(vfx):
			continue

		if vfx.trail_points.size() < 2:
			continue

		var centerline: PackedVector2Array = _build_smoothed_trail_centerline(vfx)
		var outer_color: Color = vfx.vfx_info.projectile_trail_outer_color
		var inner_color: Color = vfx.vfx_info.projectile_trail_inner_color
		_draw_projectile_trail_ribbon(centerline, vfx.vfx_info.projectile_trail_outer_width, outer_color)
		_draw_projectile_trail_ribbon(centerline, vfx.vfx_info.projectile_trail_inner_width, inner_color)

func _record_projectile_trail_point(vfx: VFXInstance) -> void: ##adds a sparse trajectory sample only after enough movement to keep ribbon geometry compact
	if not _is_projectile_trail_enabled(vfx):
		return

	if vfx.trail_points.is_empty():
		vfx.trail_points.append(vfx.position)
		return

	var last_position: Vector2 = vfx.trail_points[vfx.trail_points.size() - 1]
	var sample_distance: float = maxf(vfx.vfx_info.projectile_trail_sample_distance, 0.0)
	if last_position.distance_squared_to(vfx.position) < sample_distance * sample_distance:
		return

	vfx.trail_points.append(vfx.position)
	while vfx.trail_points.size() > maxi(vfx.vfx_info.projectile_trail_max_points, 2):
		vfx.trail_points.remove_at(0)

func _build_smoothed_trail_centerline(vfx: VFXInstance) -> PackedVector2Array: ##returns a catmull-rom smoothed center path with the current projectile position as the live head
	var control_points: PackedVector2Array = vfx.trail_points.duplicate()
	var head_index: int = control_points.size() - 1
	if head_index >= 0:
		control_points[head_index] = vfx.position

	if control_points.size() <= 2:
		return control_points

	var smoothed_points := PackedVector2Array()
	var smooth_steps: int = maxi(vfx.vfx_info.projectile_trail_smooth_steps, 1)
	for i: int in range(control_points.size() - 1):
		var p0: Vector2 = control_points[maxi(i - 1, 0)]
		var p1: Vector2 = control_points[i]
		var p2: Vector2 = control_points[i + 1]
		var p3: Vector2 = control_points[mini(i + 2, control_points.size() - 1)]

		for step: int in range(smooth_steps):
			var t: float = float(step) / float(smooth_steps)
			smoothed_points.append(_sample_catmull_rom(p0, p1, p2, p3, t))

	smoothed_points.append(control_points[control_points.size() - 1])
	return smoothed_points

func _sample_catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2: ##samples one point on a catmull-rom segment so fast projectiles leave curved rather than faceted trails
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _draw_projectile_trail_ribbon(centerline: PackedVector2Array, head_width: float, base_color: Color) -> void: ##draws one tapered polygon strip from a smoothed projectile path
	if centerline.size() < 2:
		return
	if head_width <= 0.0 or base_color.a <= 0.0:
		return

	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var left_colors := PackedColorArray()
	var right_colors := PackedColorArray()
	var point_count: int = centerline.size()

	for i: int in range(point_count):
		var progress: float = float(i) / float(point_count - 1)
		var width: float = head_width * smoothstep(0.0, 1.0, progress)
		var alpha: float = base_color.a * pow(progress, 1.35)
		var point_color: Color = Color(base_color.r, base_color.g, base_color.b, alpha)
		var normal: Vector2 = _get_trail_normal(centerline, i)

		left_edge.append(centerline[i] + normal * width * 0.5)
		left_colors.append(point_color)
		right_edge.append(centerline[i] - normal * width * 0.5)
		right_colors.append(point_color)

	var polygon_points := PackedVector2Array()
	var polygon_colors := PackedColorArray()
	for i: int in range(left_edge.size()):
		polygon_points.append(left_edge[i])
		polygon_colors.append(left_colors[i])
	for i: int in range(right_edge.size() - 1, -1, -1):
		polygon_points.append(right_edge[i])
		polygon_colors.append(right_colors[i])

	RenderingServer.canvas_item_add_polygon(_projectile_trail_canvas_item, polygon_points, polygon_colors)

func _get_trail_normal(centerline: PackedVector2Array, index: int) -> Vector2: ##uses neighbouring samples to orient ribbon width around bends
	var previous_point: Vector2 = centerline[maxi(index - 1, 0)]
	var next_point: Vector2 = centerline[mini(index + 1, centerline.size() - 1)]
	var tangent: Vector2 = next_point - previous_point
	if tangent.is_zero_approx():
		return Vector2.UP
	return tangent.normalized().orthogonal()

func _is_projectile_trail_enabled(vfx: VFXInstance) -> bool: ##checks the projectile flag plus the authored vfx trail switch before sampling or drawing trail geometry
	if DebugAssistant.disable_projectile_trails or DebugAssistant.disable_projectile_visuals:
		return false
	return vfx.is_projectile and is_instance_valid(vfx.vfx_info) and vfx.vfx_info.projectile_trail_enabled

func _push_projectile_white(color: Color) -> Color: ##brightens projectile visuals while preserving their current opacity
	var white_target: Color = Color(1.0, 1.0, 1.0, color.a)
	return color.lerp(white_target, PROJECTILE_WHITE_PUSH)

func _cleanup_vfx(vfx : VFXInstance) -> void:
	#critical: free the rid from the server to prevent memory leaks.
	RenderingServer.free_rid(vfx.canvas_item)
	_active_vfx.erase(vfx)

func apply_debug_visual_flags() -> void: ##clears currently drawn diagnostic-disabled visuals while leaving their gameplay resolvers alive
	if DebugAssistant.disable_vfx_visuals:
		_clear_active_vfx_draws()
		return

	if DebugAssistant.disable_projectile_visuals:
		RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)
		for vfx: VFXInstance in _active_vfx:
			if vfx.is_projectile:
				_clear_vfx_draw(vfx)
	elif DebugAssistant.disable_projectile_trails:
		RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)

func _clear_active_vfx_draws() -> void:
	RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)
	for vfx: VFXInstance in _active_vfx:
		_clear_vfx_draw(vfx)

func _clear_vfx_draw(vfx: VFXInstance) -> void:
	if not is_instance_valid(vfx):
		return
	if not vfx.canvas_item.is_valid():
		return

	RenderingServer.canvas_item_clear(vfx.canvas_item)

#public api
func play_vfx(
	info: VFXInfo,
	position: Vector2,
	velocity: Vector2 = Vector2.ZERO,
	lifetime: float = INF,
	scale = Vector2.ONE,
	host: Node2D = null,
	projectile_tints: Array[Color] = [],
	projectile_tint_lifetime: float = -1.0,
	starting_vertical_velocity: float = 0.0,
	arcing: bool = false,
	is_projectile: bool = false,
	vertical_gravity: float = CombatManager.PSEUDOVERTICAL_GRAVITY
) -> Variant: ##returns either vfxinstance or instantiated node, dependent on whether vfx was a scene
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"vfx_requests")
	if not info:
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return
	if DebugAssistant.disable_vfx_visuals:
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return null
	if is_projectile and DebugAssistant.disable_projectile_visuals:
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return null

	if info.is_scene:
		return _play_vfx_scene(info, position, velocity, lifetime, scale, host, projectile_tints, projectile_tint_lifetime, is_projectile)
	var vfx := VFXInstance.new()
	vfx.vfx_info = info
	vfx.position = position
	vfx.velocity = velocity
	vfx.visual_velocity = velocity
	vfx.vertical_velocity = starting_vertical_velocity
	vfx.vertical_gravity = vertical_gravity
	vfx.scale = scale * 0.06
	vfx.arcing = arcing
	vfx.is_projectile = is_projectile
	if is_projectile and info.projectile_trail_enabled:
		vfx.trail_points.append(position)
	vfx.projectile_tints = projectile_tints.duplicate()
	vfx.projectile_tint_lifetime = projectile_tint_lifetime

	if lifetime == INF: #NOTE: INF means to use info.lifetime
		vfx.lifetime = info.lifetime
	#to get a truly infinite-span projectile, use negative values (VFXInfo.INFINITE_LIFETIME)
	else:
		vfx.lifetime = lifetime

	vfx.canvas_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(vfx.canvas_item, get_viewport().world_2d.canvas)
	RenderingServer.canvas_item_set_z_index(vfx.canvas_item, vfx.vfx_info.graphical_layer)
	#attach our orphan canvas item to the world canvas
	_active_vfx.append(vfx)
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"vfx_instances_created")
	set_process(true)
	return vfx

func play_ballistic_vfx(
	info: VFXInfo,
	start_position: Vector2,
	end_position: Vector2,
	projectile_speed: float,
	vertical_gravity: float,
	minimum_flight_time: float = 0.0,
	maximum_flight_time: float = INF,
	scale: Vector2 = Vector2.ONE,
	is_projectile: bool = false
) -> Variant: ##launches a purely cosmetic vfx along a point-to-point pseudovertical arc without creating a combat resolver
	if not is_instance_valid(info):
		return null
	if start_position.is_equal_approx(end_position):
		return null
	if projectile_speed <= 0.0:
		return null

	var safe_minimum_time: float = maxf(minimum_flight_time, 0.0)
	var flight_time: float = maxf(start_position.distance_to(end_position) / projectile_speed, safe_minimum_time)
	if maximum_flight_time >= 0.0:
		flight_time = minf(flight_time, maxf(maximum_flight_time, safe_minimum_time))
	if flight_time <= 0.0:
		return null

	var velocity: Vector2 = (end_position - start_position) / flight_time
	var starting_vertical_velocity: float = -0.5 * vertical_gravity * flight_time
	return play_vfx(
		info,
		start_position,
		velocity,
		flight_time,
		scale,
		null,
		[],
		flight_time,
		starting_vertical_velocity,
		not is_zero_approx(vertical_gravity),
		is_projectile,
		vertical_gravity
	)

func sync_projectile_vfx(vfx_instance: Variant, position: Vector2, visual_velocity: Vector2) -> void: ##updates externally simulated projectile visuals while preserving their sampled trail history
	if not is_instance_valid(vfx_instance):
		return

	if vfx_instance is VFXInstance:
		var vfx: VFXInstance = vfx_instance
		vfx.position = position
		vfx.visual_velocity = visual_velocity
		_record_projectile_trail_point(vfx)
		return

	if vfx_instance is Node2D:
		var node_vfx: Node2D = vfx_instance
		node_vfx.global_position = position

func play_aoe_field(
	info: VFXInfo,
	position: Vector2,
	radius: float,
	cone_angle_deg: float = 360.0,
	aim_direction: Vector2 = Vector2.RIGHT
) -> AoeParticleFieldVFX: ##spawns a dense marker field for circular or cone aoes using the per-resource authored particle settings
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"aoe_field_requests")
	if DebugAssistant.disable_vfx_visuals:
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return null

	if not info or not info.aoe_particles_enabled:
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return null

	if radius <= 0.0 or not is_instance_valid(info.aoe_particle_texture):
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return null

	var field := AoeParticleFieldVFX.new()

	var parent: Node = Run.references.projectiles if is_instance_valid(Run.references.projectiles) else Run.references.island
	if not is_instance_valid(parent):
		parent = self

	parent.add_child(field)
	field.global_position = position
	field.setup_from_info(info, radius, cone_angle_deg, aim_direction)
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"aoe_field_instances_created")
	return field

func play_swirl_line(
	start_position: Vector2,
	end_position: Vector2,
	color: Color,
	width: float = 10.0,
	lifetime: float = 0.35,
	particles_per_tile: float = 2.0,
	scale_min: float = 0.45,
	scale_max: float = 0.85,
	drift_speed_min: float = 4.0,
	drift_speed_max: float = 12.0,
	drift_angle_noise_deg: float = 35.0,
	graphical_layer: int = Layers.ALLIED_PROJECTILES
) -> SwirlLineVFX: ##spawns a short-lived swirl-particle line with one compact call so support links can telegraph themselves without bespoke scene setup
	if DebugAssistant.disable_vfx_visuals:
		return null

	if start_position.is_equal_approx(end_position):
		return null

	var line := SwirlLineVFX.new()
	line.z_index = graphical_layer
	line.z_as_relative = false

	var parent: Node = Run.references.projectiles if is_instance_valid(Run.references.projectiles) else Run.references.island
	if not is_instance_valid(parent):
		parent = self

	parent.add_child(line)
	line.global_position = Vector2.ZERO
	line.configure(
		start_position,
		end_position,
		color,
		width,
		lifetime,
		particles_per_tile,
		scale_min,
		scale_max,
		drift_speed_min,
		drift_speed_max,
		drift_angle_noise_deg
	)
	return line

func play_swirl_line_info(info: VFXInfo, start_position: Vector2, end_position: Vector2) -> SwirlLineVFX: ##spawns a pulse swirl line from one authored resource so behaviors do not have to inline beam tuning
	if not is_instance_valid(info):
		return null

	var line: SwirlLineVFX = play_swirl_line(
		start_position,
		end_position,
		info.swirl_color,
		info.swirl_width,
		info.lifetime,
		info.swirl_particles_per_tile,
		info.swirl_scale_min,
		info.swirl_scale_max,
		info.swirl_drift_speed_min,
		info.swirl_drift_speed_max,
		info.swirl_drift_angle_noise_deg,
		info.graphical_layer
	)
	if is_instance_valid(line):
		line.set_texture(info.swirl_particle_texture)
	return line

func create_swirl_beam(
	start_position: Vector2,
	end_position: Vector2,
	color: Color,
	width: float = 10.0,
	particle_lifetime: float = 0.35,
	particles_per_tile: float = 2.0,
	scale_min: float = 0.45,
	scale_max: float = 0.85,
	drift_speed_min: float = 4.0,
	drift_speed_max: float = 12.0,
	drift_angle_noise_deg: float = 35.0,
	graphical_layer: int = Layers.ALLIED_PROJECTILES
) -> SwirlLineVFX: ##spawns a persistent diffuse swirl beam that the caller can keep repositioning while a link stays active
	if DebugAssistant.disable_vfx_visuals:
		return null

	if start_position.is_equal_approx(end_position):
		return null

	var beam := SwirlLineVFX.new()
	beam.z_index = graphical_layer
	beam.z_as_relative = false

	var parent: Node = Run.references.projectiles if is_instance_valid(Run.references.projectiles) else Run.references.island
	if not is_instance_valid(parent):
		parent = self

	parent.add_child(beam)
	beam.global_position = Vector2.ZERO
	beam.configure_persistent(
		start_position,
		end_position,
		color,
		width,
		particle_lifetime,
		particles_per_tile,
		scale_min,
		scale_max,
		drift_speed_min,
		drift_speed_max,
		drift_angle_noise_deg
	)
	return beam

func create_swirl_beam_info(info: VFXInfo, start_position: Vector2, end_position: Vector2, strength: float = 1.0) -> SwirlLineVFX: ##spawns a persistent swirl beam from one authored resource so linked supports stay data-driven
	if not is_instance_valid(info):
		return null
	if strength <= 0.0:
		return null

	var beam_color: Color = info.swirl_color
	beam_color.a *= strength

	var beam: SwirlLineVFX = create_swirl_beam(
		start_position,
		end_position,
		beam_color,
		info.swirl_width,
		info.lifetime,
		info.swirl_particles_per_tile * strength,
		info.swirl_scale_min,
		info.swirl_scale_max,
		info.swirl_drift_speed_min,
		info.swirl_drift_speed_max,
		info.swirl_drift_angle_noise_deg,
		info.graphical_layer
	)
	if is_instance_valid(beam):
		beam.set_texture(info.swirl_particle_texture)
	return beam

func _play_vfx_scene(info: VFXInfo, pos: Vector2, velocity: Vector2, lifetime: float, scale: Vector2, host: Node2D, projectile_tints: Array[Color], projectile_tint_lifetime: float, is_projectile: bool = false) -> Node2D:
	if not info.scene:
		push_warning("VFX: ", host, " tried to create vfx without valid scene")

	var instance: Node2D
	var is_new: bool = false

	if info.is_persistent and is_instance_valid(host):
		#use a unique meta key based on the VFXInfo resource ID to track the instance
		var meta_key: String = "vfx_persist_" + str(abs(info.get_instance_id()))
		#NOTE: abs is to filter out hyphens, which form invalid keys
		if host.has_meta(meta_key):
			instance = host.get_meta(meta_key)
			if not is_instance_valid(instance):
				instance = null #instance freed somehow?
		if not instance:
			instance = info.scene.instantiate() as Node2D
			host.add_child(instance)
			host.set_meta(meta_key, instance)
			is_new = true
	else:
		instance = info.scene.instantiate() as Node2D
		if is_instance_valid(Run.references.island):
			Run.references.island.add_child(instance)

	#contract
	instance.z_index = Layers.ALLIED_PROJECTILES
	instance.z_as_relative = false
	instance.global_position = pos
	instance.scale = scale * 0.06
	#setup
	var host_unit: Unit = host as Unit
	if is_instance_valid(host_unit) and is_instance_valid(host.attack_component):
		if instance is RadialPulseVFX:
			host_unit.attack_component.setup_radial_pulse(instance as RadialPulseVFX, info)

	if "velocity" in instance:
		instance.velocity = velocity

	if instance is CanvasItem and (is_projectile or not projectile_tints.is_empty()):
		_register_scene_tint(instance as CanvasItem, lifetime, projectile_tints, projectile_tint_lifetime, is_projectile)

	if instance.has_method("reset"):
		instance.reset()
	else:
		push_warning("VFX: ", instance, " lacks reset!")
	if instance.has_method("start"):
		instance.start()
	else:
		push_warning("VFX: ", instance, " lacks start!")

	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"vfx_scene_instances_created")
	return instance

func _register_scene_tint(canvas_item: CanvasItem, lifetime: float, projectile_tints: Array[Color], projectile_tint_lifetime: float, white_push_enabled: bool = false) -> void: ##tracks scene-backed projectile visuals in the same tint-cycle system used by procedural projectile sprites
	for scene_tint: SceneTintState in _active_scene_tints:
		if scene_tint.canvas_item != canvas_item:
			continue

		scene_tint.base_modulate = canvas_item.modulate
		scene_tint.projectile_tints = projectile_tints.duplicate()
		scene_tint.lifetime = lifetime
		scene_tint.tint_cycle_lifetime = projectile_tint_lifetime
		scene_tint.white_push_enabled = white_push_enabled
		scene_tint.age = 0.0
		return

	var scene_tint := SceneTintState.new()
	scene_tint.canvas_item = canvas_item
	scene_tint.base_modulate = canvas_item.modulate
	scene_tint.projectile_tints = projectile_tints.duplicate()
	scene_tint.lifetime = lifetime
	scene_tint.tint_cycle_lifetime = projectile_tint_lifetime
	scene_tint.white_push_enabled = white_push_enabled
	_active_scene_tints.append(scene_tint)
	set_process(true)

func _get_projectile_tint(projectile_tints: Array[Color], age: float, lifetime_basis: float) -> Color: ##returns the current projectile tint by cycling across the authored palette instead of blending all effects into one muddy color
	if projectile_tints.is_empty():
		return Color.WHITE

	if projectile_tints.size() == 1:
		return projectile_tints[0]

	var cycle_time: float = _get_projectile_tint_cycle_time(lifetime_basis)
	var segment_progress: float = age / cycle_time
	var current_index: int = int(floor(segment_progress)) % projectile_tints.size()
	var next_index: int = (current_index + 1) % projectile_tints.size()
	var blend_weight: float = segment_progress - floor(segment_progress)
	return projectile_tints[current_index].lerp(projectile_tints[next_index], blend_weight)

func _get_projectile_tint_cycle_time(lifetime_basis: float) -> float: ##derives the per-tint blend duration from projectile lifetime while clamping extreme short and long shots into a readable cadence
	if lifetime_basis <= 0.0:
		return MIN_PROJECTILE_TINT_CYCLE_TIME

	return clampf(
		lifetime_basis * PROJECTILE_TINT_CYCLE_PROPORTION,
		MIN_PROJECTILE_TINT_CYCLE_TIME,
		MAX_PROJECTILE_TINT_CYCLE_TIME
	)
