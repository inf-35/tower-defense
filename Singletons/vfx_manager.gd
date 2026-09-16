extends Node
#VFXManager. Bypasses the scene tree and calls the renderingserver directly
const PROJECTILE_TINT_CYCLE_PROPORTION: float = 0.4 ##per-tint blend duration expressed as a proportion of the projectile lifetime basis
const MIN_PROJECTILE_TINT_CYCLE_TIME: float = 0.12 ##lower clamp for per-tint blend duration so short-lived projectiles do not flicker through colors too quickly
const MAX_PROJECTILE_TINT_CYCLE_TIME: float = 0.6 ##upper clamp for per-tint blend duration so long-lived projectiles still cycle visibly before impact
const PROJECTILE_WHITE_PUSH: float = 0.0 ##fraction of each projectile tint blended toward white so shots read crisply against terrain
const EXEMPT_PROJECTILE_CANVAS_LAYER: int = 1
const META_EXEMPT_PROJECTILE_VFX: StringName = &"exempt_projectile_vfx"
const DEFAULT_PROJECTILE_CHROMA_MULTIPLIER: float = 1.0
const DEFAULT_PROJECTILE_CHROMA_ALPHA: float = 0.34
const DEFAULT_PROJECTILE_CHROMA_SCALE: float = 1.85
const DEFAULT_PROJECTILE_CHROMA_BOOST: float = 0.75
const DEFAULT_PROJECTILE_NIGHT_SHADING_FRACTION: float = 0.9
const PROJECTILE_TEXTURE_BATCH_INITIAL_CAPACITY: int = 32
const PROJECTILE_TEXTURE_BATCH_AABB: AABB = AABB(Vector3(-100000.0, -100000.0, -1.0), Vector3(200000.0, 200000.0, 2.0))


class SceneTintState extends RefCounted:
	var canvas_item: CanvasItem
	var base_modulate: Color = Color.WHITE
	var projectile_tints: Array[Color] = []
	var white_push_enabled: bool = false
	var chroma_strength: float = 0.0
	var age: float = 0.0
	var lifetime: float = 0.0
	var tint_cycle_lifetime: float = -1.0

class ProjectileTextureBatch extends RefCounted:
	var texture: Texture2D
	var layer: int = Layers.ALLIED_PROJECTILES
	var mesh: QuadMesh
	var base_instance: MultiMeshInstance2D
	var base_multimesh: MultiMesh
	var chroma_instance: MultiMeshInstance2D
	var chroma_multimesh: MultiMesh
	var capacity: int = 0
	var base_count: int = 0
	var chroma_count: int = 0

var _active_vfx: Array[VFXInstance] = []
var _active_scene_tints: Array[SceneTintState] = []
var _active_exempt_nodes: Array[Node2D] = []
var _projectile_texture_batches: Dictionary[String, ProjectileTextureBatch] = {}
var _projectile_canvas_layer: CanvasLayer
var _projectile_canvas_root: Node2D
var _projectile_trail_canvas_item: RID
var _projectile_chroma_canvas_item: RID
var _projectile_chroma_material: CanvasItemMaterial
#a flat array allows for optimal memory access

func _ready() -> void: ##registers the render-server draw hook while leaving per-frame simulation asleep until effects exist
	#we draw our effects ourselves during the frame_post_draw signal.
	set_process(false)
	_setup_exempt_projectile_canvas()
	_projectile_trail_canvas_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_projectile_trail_canvas_item, _get_projectile_canvas_parent())
	RenderingServer.canvas_item_set_z_index(_projectile_trail_canvas_item, Layers.ALLIED_PROJECTILES + 1)
	_projectile_chroma_canvas_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_projectile_chroma_canvas_item, _get_projectile_canvas_parent())
	RenderingServer.canvas_item_set_z_index(_projectile_chroma_canvas_item, Layers.ALLIED_PROJECTILES)
	_projectile_chroma_material = CanvasItemMaterial.new()
	_projectile_chroma_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	RenderingServer.canvas_item_set_material(_projectile_chroma_canvas_item, _projectile_chroma_material.get_rid())
	RenderingServer.frame_post_draw.connect(_draw_vfx)

func _exit_tree() -> void: ##releases render-server resources owned by the exempt projectile pass
	if RenderingServer.frame_post_draw.is_connected(_draw_vfx):
		RenderingServer.frame_post_draw.disconnect(_draw_vfx)
	for batch: ProjectileTextureBatch in _projectile_texture_batches.values():
		if is_instance_valid(batch.base_instance):
			batch.base_instance.queue_free()
		if is_instance_valid(batch.chroma_instance):
			batch.chroma_instance.queue_free()
	_projectile_texture_batches.clear()
	if _projectile_trail_canvas_item.is_valid():
		RenderingServer.free_rid(_projectile_trail_canvas_item)
	if _projectile_chroma_canvas_item.is_valid():
		RenderingServer.free_rid(_projectile_chroma_canvas_item)

func _setup_exempt_projectile_canvas() -> void: ##creates an unmodulated world-following pass for projectile visuals and trails
	_projectile_canvas_layer = CanvasLayer.new()
	_projectile_canvas_layer.name = "ExemptProjectileCanvasLayer"
	_projectile_canvas_layer.layer = EXEMPT_PROJECTILE_CANVAS_LAYER
	add_child(_projectile_canvas_layer)

	_projectile_canvas_root = Node2D.new()
	_projectile_canvas_root.name = "ExemptProjectileCanvasRoot"
	_projectile_canvas_layer.add_child(_projectile_canvas_root)
	_sync_projectile_canvas_transform()

func _can_use_projectile_texture_multimesh(info: VFXInfo, is_projectile: bool) -> bool: ##returns true for simple projectile textures that can share one multimesh draw path
	if not is_projectile:
		return false
	if not is_instance_valid(_projectile_canvas_root):
		return false
	if not is_instance_valid(info):
		return false
	if info.vfx_type != VFXInfo.VFXType.TEXTURE:
		return false
	if not is_instance_valid(info.texture):
		return false
	return info.h_frames <= 1 and info.v_frames <= 1

func _get_projectile_texture_batch(info: VFXInfo) -> ProjectileTextureBatch: ##returns the per-texture projectile batch, creating its draw nodes on first use
	var key: String = _get_projectile_texture_batch_key(info)
	var existing: ProjectileTextureBatch = _projectile_texture_batches.get(key, null)
	if existing != null:
		return existing

	if not is_instance_valid(_projectile_canvas_root):
		push_error("VFXManager: exempt projectile canvas root missing; texture projectile batch cannot render.")
		return null

	var batch := ProjectileTextureBatch.new()
	batch.texture = info.texture
	batch.layer = info.graphical_layer
	batch.mesh = QuadMesh.new()
	batch.mesh.size = Vector2(float(info.texture.get_width()), float(info.texture.get_height()))
	batch.base_multimesh = _create_projectile_texture_multimesh(batch.mesh)
	batch.chroma_multimesh = _create_projectile_texture_multimesh(batch.mesh)
	batch.base_instance = _create_projectile_texture_multimesh_instance("ProjectileTextureBatch", batch.texture, batch.base_multimesh, batch.layer, false)
	batch.chroma_instance = _create_projectile_texture_multimesh_instance("ProjectileTextureChromaBatch", batch.texture, batch.chroma_multimesh, Layers.ALLIED_PROJECTILES, true)
	_projectile_canvas_root.add_child(batch.chroma_instance)
	_projectile_canvas_root.add_child(batch.base_instance)
	_projectile_texture_batches[key] = batch
	return batch

func _get_projectile_texture_batch_key(info: VFXInfo) -> String: ##keeps multimesh buckets separated by texture resource and z layer
	return "%s:%s" % [info.texture.get_instance_id(), info.graphical_layer]

func _create_projectile_texture_multimesh(mesh: QuadMesh) -> MultiMesh: ##creates one growable multimesh buffer for projectile texture instances
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = false
	multimesh.mesh = mesh
	multimesh.custom_aabb = PROJECTILE_TEXTURE_BATCH_AABB
	multimesh.instance_count = 0
	multimesh.visible_instance_count = 0
	return multimesh

func _create_projectile_texture_multimesh_instance(instance_name: String, texture: Texture2D, multimesh: MultiMesh, layer: int, additive: bool) -> MultiMeshInstance2D: ##creates one canvas item that draws many same-texture projectile quads
	var instance := MultiMeshInstance2D.new()
	instance.name = instance_name
	instance.texture = texture
	instance.multimesh = multimesh
	instance.z_index = layer
	instance.z_as_relative = false
	instance.visible = false
	if additive:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		instance.material = material
	return instance

func _ensure_projectile_texture_batch_capacity(batch: ProjectileTextureBatch, required: int) -> void: ##grows base and chroma buffers together so per-frame writes stay index-safe
	if batch.capacity >= required:
		return

	var next_capacity: int = maxi(batch.capacity, PROJECTILE_TEXTURE_BATCH_INITIAL_CAPACITY)
	while next_capacity < required:
		next_capacity *= 2

	batch.capacity = next_capacity
	batch.base_multimesh.instance_count = next_capacity
	batch.chroma_multimesh.instance_count = next_capacity

func _get_projectile_canvas_parent() -> RID: ##returns the render-server parent for projectiles that bypass combat-night canvas modulation
	if is_instance_valid(_projectile_canvas_root):
		return _projectile_canvas_root.get_canvas_item()
	push_error("VFXManager: exempt projectile canvas root missing; procedural projectile vfx will render on the shaded world canvas.")
	return get_viewport().world_2d.canvas

func _get_vfx_canvas_parent(is_projectile: bool) -> RID: ##keeps ordinary vfx in the world pass while routing projectiles into the exempt pass
	if is_projectile:
		return _get_projectile_canvas_parent()
	return get_viewport().world_2d.canvas

func _sync_projectile_canvas_transform() -> void: ##makes the exempt canvas accept world-space positions while avoiding world-canvas modulation
	if is_instance_valid(_projectile_canvas_root):
		_projectile_canvas_root.transform = get_viewport().get_canvas_transform()

func add_exempt_node(node: Node2D, world_position: Vector2) -> bool: ##parents world-space nodes through the unshaded projectile bridge
	if not is_instance_valid(_projectile_canvas_root):
		push_error("VFXManager: exempt projectile canvas root missing; exempt world node cannot render unshaded.")
		node.queue_free()
		return false

	_projectile_canvas_root.add_child(node)
	node.set_meta(META_EXEMPT_PROJECTILE_VFX, true)
	node.position = world_position
	_active_exempt_nodes.append(node)
	set_process(true)
	return true

func _process(_d: float) -> void: ##advances procedural vfx and scene tint cycles only while one of those systems has live work
	_sync_projectile_canvas_transform()
	for index: int in range(_active_exempt_nodes.size() - 1, -1, -1):
		if not is_instance_valid(_active_exempt_nodes[index]):
			_active_exempt_nodes.remove_at(index)
	var delta: float = Clock.game_delta
	if _active_vfx.is_empty() and _active_scene_tints.is_empty():
		if _active_exempt_nodes.is_empty():
			set_process(false)
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
			current_modulate = _apply_projectile_night_shading(current_modulate)
		if scene_tint.chroma_strength > 0.0:
			current_modulate = _boost_projectile_chroma(current_modulate, scene_tint.chroma_strength * _get_projectile_chroma_multiplier())
		scene_tint.canvas_item.modulate = current_modulate

		if scene_tint.lifetime > 0.0 and scene_tint.age >= scene_tint.lifetime:
			scene_tints_to_remove.append(scene_tint)

	for scene_tint: SceneTintState in scene_tints_to_remove:
		_active_scene_tints.erase(scene_tint)

	if _active_vfx.is_empty() and _active_scene_tints.is_empty() and _active_exempt_nodes.is_empty():
		set_process(false)

func _draw_vfx() -> void: ##redraws all procedural vfx plus one shared projectile-trail canvas item on the render server
	_sync_projectile_canvas_transform()
	_begin_projectile_texture_batches()
	if _projectile_chroma_canvas_item.is_valid():
		RenderingServer.canvas_item_clear(_projectile_chroma_canvas_item)
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
			current_color = _apply_projectile_night_shading(current_color)
		if vfx.uses_projectile_texture_multimesh:
			_submit_projectile_texture_batch(vfx, info, current_scale_val, current_color)
			continue
		#critical: we must clear the canvas item before drawing the new frame.
		RenderingServer.canvas_item_clear(canvas_item_rid)

		_draw_vfx_shape(canvas_item_rid, vfx, info, current_scale_val, current_color)
		if vfx.is_projectile:
			_draw_projectile_chroma(vfx, info, current_scale_val, current_color)
	_flush_projectile_texture_batches()

func _begin_projectile_texture_batches() -> void: ##resets transient per-frame counts before active projectiles repopulate the multimesh buffers
	for batch: ProjectileTextureBatch in _projectile_texture_batches.values():
		batch.base_count = 0
		batch.chroma_count = 0

func _flush_projectile_texture_batches() -> void: ##publishes populated multimesh instance counts and hides empty projectile batches
	for batch: ProjectileTextureBatch in _projectile_texture_batches.values():
		if is_instance_valid(batch.base_multimesh):
			batch.base_multimesh.visible_instance_count = batch.base_count
		if is_instance_valid(batch.base_instance):
			batch.base_instance.visible = batch.base_count > 0
		if is_instance_valid(batch.chroma_multimesh):
			batch.chroma_multimesh.visible_instance_count = batch.chroma_count
		if is_instance_valid(batch.chroma_instance):
			batch.chroma_instance.visible = batch.chroma_count > 0

func _clear_projectile_texture_batches() -> void: ##hides batched projectile texture draws without touching their gameplay state
	for batch: ProjectileTextureBatch in _projectile_texture_batches.values():
		batch.base_count = 0
		batch.chroma_count = 0
		if is_instance_valid(batch.base_multimesh):
			batch.base_multimesh.visible_instance_count = 0
		if is_instance_valid(batch.base_instance):
			batch.base_instance.visible = false
		if is_instance_valid(batch.chroma_multimesh):
			batch.chroma_multimesh.visible_instance_count = 0
		if is_instance_valid(batch.chroma_instance):
			batch.chroma_instance.visible = false

func _submit_projectile_texture_batch(vfx: VFXInstance, info: VFXInfo, current_scale_val: float, current_color: Color) -> void: ##writes one simple texture projectile into its shared base and chroma multimesh buffers
	var batch: ProjectileTextureBatch = _get_projectile_texture_batch(info)
	if batch == null:
		return

	batch.base_count += 1
	_ensure_projectile_texture_batch_capacity(batch, batch.base_count)
	_set_projectile_texture_multimesh_item(batch.base_multimesh, batch.base_count - 1, vfx, current_scale_val, current_color, 1.0)

	var strength: float = vfx.projectile_chroma_strength * _get_projectile_chroma_multiplier()
	if strength <= 0.0:
		return

	batch.chroma_count += 1
	_ensure_projectile_texture_batch_capacity(batch, maxi(batch.base_count, batch.chroma_count))
	var chroma_color: Color = _get_projectile_chroma_color(current_color, strength)
	_set_projectile_texture_multimesh_item(batch.chroma_multimesh, batch.chroma_count - 1, vfx, current_scale_val, chroma_color, _get_projectile_chroma_scale(strength))

func _set_projectile_texture_multimesh_item(multimesh: MultiMesh, index: int, vfx: VFXInstance, current_scale_val: float, color: Color, scale_multiplier: float) -> void: ##stores transform and tint data for one projectile texture instance
	var draw_scale: float = current_scale_val * scale_multiplier
	var transform: Transform2D = Transform2D(vfx.rotation, Vector2.ZERO).scaled(Vector2(draw_scale, draw_scale))
	transform = transform.translated(vfx.position)
	multimesh.set_instance_transform_2d(index, transform)
	multimesh.set_instance_color(index, color)

func _draw_vfx_shape(canvas_item_rid: RID, vfx: VFXInstance, info: VFXInfo, current_scale_val: float, current_color: Color, scale_multiplier: float = 1.0) -> void: ##draws one procedural vfx shape onto the requested render-server canvas item
	if not canvas_item_rid.is_valid():
		return

	var draw_scale: float = current_scale_val * scale_multiplier
	var transform: Transform2D = Transform2D(vfx.rotation, Vector2.ZERO).scaled(Vector2(draw_scale, draw_scale))
	transform = transform.translated(vfx.position)
	RenderingServer.canvas_item_add_set_transform(canvas_item_rid, transform)

	match info.vfx_type:
		VFXInfo.VFXType.TEXTURE:
			if not is_instance_valid(info.texture):
				return

			var frame := int(vfx.age * info.fps) % (info.h_frames * info.v_frames)
			var fx: int = frame % info.h_frames
			@warning_ignore_start("integer_division")
			var fy: int = frame / info.h_frames
			var region_w = info.texture.get_width() / info.h_frames
			var region_h = info.texture.get_height() / info.v_frames
			var region: Rect2 = Rect2(fx * region_w, fy * region_h, region_w, region_h)
			var draw_rect: Rect2 = Rect2(-region.size * 0.5, region.size)
			RenderingServer.canvas_item_add_texture_rect_region(canvas_item_rid, draw_rect, info.texture.get_rid(), region, current_color)

		VFXInfo.VFXType.CIRCLE:
			var radius: float = vfx.scale.x * info.radius * draw_scale
			RenderingServer.canvas_item_add_circle(canvas_item_rid, Vector2.ZERO, radius, current_color)

		VFXInfo.VFXType.RECTANGLE:
			var size: Vector2 = vfx.scale * info.size * draw_scale
			var rect: Rect2 = Rect2(-size / 2.0, size)
			if info.filled:
				RenderingServer.canvas_item_add_rect(canvas_item_rid, rect, current_color)
			else:
				var corners: PackedVector2Array = [
					rect.position,
					Vector2(rect.position.x + rect.size.x, rect.position.y),
					rect.position + rect.size,
					Vector2(rect.position.x, rect.position.y + rect.size.y)
				]
				RenderingServer.canvas_item_add_polyline(canvas_item_rid, corners, [current_color], info.primitive_width)

func _draw_projectile_chroma(vfx: VFXInstance, info: VFXInfo, current_scale_val: float, current_color: Color) -> void: ##draws the additive projectile chroma copy on the exempt projectile pass
	if not _projectile_chroma_canvas_item.is_valid():
		return

	var strength: float = vfx.projectile_chroma_strength * _get_projectile_chroma_multiplier()
	if strength <= 0.0:
		return

	var chroma_color: Color = _get_projectile_chroma_color(current_color, strength)
	var scale_multiplier: float = _get_projectile_chroma_scale(strength)
	_draw_vfx_shape(_projectile_chroma_canvas_item, vfx, info, current_scale_val, chroma_color, scale_multiplier)

func _draw_projectile_trails() -> void: ##draws projectile trails as centralized smoothed ribbon geometry on the exempt projectile pass
	RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)
	if DebugAssistant.disable_projectile_trails or DebugAssistant.disable_projectile_visuals:
		return

	for vfx: VFXInstance in _active_vfx:
		if not _is_projectile_trail_enabled(vfx):
			continue
		if vfx.trail_points.size() < 2:
			continue

		var centerline: PackedVector2Array = _build_smoothed_trail_centerline(vfx)
		var head_index: int = centerline.size() - 1
		centerline = _extend_projectile_trail_head(vfx, centerline)
		var outer_color: Color = _apply_projectile_night_shading(vfx.vfx_info.projectile_trail_outer_color)
		var inner_color: Color = _apply_projectile_night_shading(vfx.vfx_info.projectile_trail_inner_color)
		_draw_projectile_trail_chroma(vfx, centerline, head_index, outer_color, inner_color)
		_draw_projectile_trail_ribbon(_projectile_trail_canvas_item, centerline, head_index, vfx.vfx_info.projectile_trail_outer_width, outer_color)
		_draw_projectile_trail_ribbon(_projectile_trail_canvas_item, centerline, head_index, vfx.vfx_info.projectile_trail_inner_width, inner_color)

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

func _extend_projectile_trail_head(vfx: VFXInstance, centerline: PackedVector2Array) -> PackedVector2Array: ##adds a short fade-only continuation so projectile trails avoid hard head caps
	if centerline.size() < 2:
		return centerline

	var extension: float = maxf(vfx.vfx_info.projectile_trail_head_extension, 0.0)
	if extension <= 0.0:
		return centerline

	var heading: Vector2 = _get_projectile_trail_heading(vfx, centerline)
	if heading.is_zero_approx():
		return centerline

	var extended_line: PackedVector2Array = centerline.duplicate()
	var head: Vector2 = centerline[centerline.size() - 1]
	var steps: int = maxi(vfx.vfx_info.projectile_trail_head_extension_steps, 1)
	for step: int in range(1, steps + 1):
		var progress: float = float(step) / float(steps)
		extended_line.append(head + heading * extension * progress)

	return extended_line

func _get_projectile_trail_heading(vfx: VFXInstance, centerline: PackedVector2Array) -> Vector2: ##prefers drawn path direction, falling back to projectile velocity for fresh trails
	var head: Vector2 = centerline[centerline.size() - 1]
	var previous: Vector2 = centerline[centerline.size() - 2]
	var path_heading: Vector2 = head - previous
	if not path_heading.is_zero_approx():
		return path_heading.normalized()
	if not vfx.visual_velocity.is_zero_approx():
		return vfx.visual_velocity.normalized()
	if not vfx.velocity.is_zero_approx():
		return vfx.velocity.normalized()
	return Vector2.ZERO

func _sample_catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2: ##samples one point on a catmull-rom segment so fast projectiles leave curved rather than faceted trails
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)

func _draw_projectile_trail_chroma(vfx: VFXInstance, centerline: PackedVector2Array, head_index: int, outer_color: Color, inner_color: Color) -> void: ##draws one wide additive ribbon behind exempt projectile trails
	if not _projectile_chroma_canvas_item.is_valid():
		return

	var strength: float = vfx.projectile_trail_chroma_strength * _get_projectile_chroma_multiplier()
	if strength <= 0.0:
		return

	var base_color: Color = outer_color.lerp(inner_color, 0.35)
	var chroma_color: Color = _get_projectile_chroma_color(base_color, strength)
	var head_width: float = maxf(vfx.vfx_info.projectile_trail_outer_width, vfx.vfx_info.projectile_trail_inner_width)
	head_width *= _get_projectile_chroma_scale(strength)
	_draw_projectile_trail_ribbon(_projectile_chroma_canvas_item, centerline, head_index, head_width, chroma_color)

func _draw_projectile_trail_ribbon(canvas_item_rid: RID, centerline: PackedVector2Array, head_index: int, head_width: float, base_color: Color) -> void: ##draws one tapered polygon strip from a smoothed projectile path
	if not canvas_item_rid.is_valid():
		return
	if centerline.size() < 2:
		return
	if head_width <= 0.0 or base_color.a <= 0.0:
		return

	RenderingServer.canvas_item_add_set_transform(canvas_item_rid, Transform2D.IDENTITY)

	var left_edge := PackedVector2Array()
	var right_edge := PackedVector2Array()
	var left_colors := PackedColorArray()
	var right_colors := PackedColorArray()
	var point_count: int = centerline.size()
	var fade_start_index: int = clampi(head_index, 1, point_count - 1)
	var fade_length: int = maxi(point_count - 1 - fade_start_index, 1)

	for i: int in range(point_count):
		var trail_progress: float = minf(float(i) / float(fade_start_index), 1.0)
		var head_fade: float = 1.0
		if i > fade_start_index:
			var fade_progress: float = float(i - fade_start_index) / float(fade_length)
			head_fade = 1.0 - smoothstep(0.0, 1.0, fade_progress)
		var width: float = head_width * smoothstep(0.0, 1.0, trail_progress) * head_fade
		var alpha: float = base_color.a * pow(trail_progress, 1.35) * head_fade
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

	RenderingServer.canvas_item_add_polygon(canvas_item_rid, polygon_points, polygon_colors)

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

func _apply_projectile_night_shading(color: Color) -> Color: ##reapplies an authored fraction of combat-night tint to exempt projectile visuals
	if not _is_combat_night_active():
		return color

	var shade_fraction: float = _get_projectile_night_shading_fraction()
	if shade_fraction <= 0.0:
		return color

	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return color

	var ambient: Color = profile.night_ambient_color
	var shaded_color: Color = Color(color.r * ambient.r, color.g * ambient.g, color.b * ambient.b, color.a)
	return color.lerp(shaded_color, shade_fraction)

func _is_combat_night_active() -> bool: ##matches the phase window where combat lighting would normally modulate world-space projectiles
	if DebugAssistant.disable_combat_lighting:
		return false
	return is_instance_valid(Run.phases) and Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE

func _boost_projectile_chroma(color: Color, strength: float) -> Color: ##raises projectile colour separation without changing its opacity
	var boost: float = 1.0 + _get_projectile_chroma_boost() * maxf(strength, 0.0)
	var luminance: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return Color(
		clampf(luminance + (color.r - luminance) * boost, 0.0, 1.0),
		clampf(luminance + (color.g - luminance) * boost, 0.0, 1.0),
		clampf(luminance + (color.b - luminance) * boost, 0.0, 1.0),
		color.a
	)

func _get_projectile_chroma_color(color: Color, strength: float) -> Color: ##converts a projectile colour into an additive glow colour for the exempt chroma pass
	var boosted_color: Color = _boost_projectile_chroma(color, strength)
	boosted_color.a = clampf(color.a * _get_projectile_chroma_alpha() * strength, 0.0, 1.0)
	return boosted_color

func _get_projectile_chroma_scale(strength: float) -> float: ##interpolates from exact projectile size toward the environment-authored glow footprint
	var scale_target: float = maxf(_get_projectile_chroma_scale_target(), 1.0)
	return lerpf(1.0, scale_target, clampf(strength, 0.0, 1.0))

func _get_projectile_chroma_multiplier() -> float: ##reads the active environment's global projectile-chroma intensity
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return DEFAULT_PROJECTILE_CHROMA_MULTIPLIER
	return maxf(profile.night_projectile_chroma_multiplier, 0.0)

func _get_projectile_chroma_alpha() -> float: ##reads the active environment's additive projectile-chroma opacity basis
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return DEFAULT_PROJECTILE_CHROMA_ALPHA
	return clampf(profile.night_projectile_chroma_alpha, 0.0, 1.0)

func _get_projectile_chroma_scale_target() -> float: ##reads the active environment's projectile-chroma footprint
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return DEFAULT_PROJECTILE_CHROMA_SCALE
	return maxf(profile.night_projectile_chroma_scale, 1.0)

func _get_projectile_chroma_boost() -> float: ##reads the active environment's projectile saturation lift
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return DEFAULT_PROJECTILE_CHROMA_BOOST
	return maxf(profile.night_projectile_chroma_boost, 0.0)

func _get_projectile_night_shading_fraction() -> float: ##reads how much combat-night tint should be reapplied to the exempt projectile pass
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return DEFAULT_PROJECTILE_NIGHT_SHADING_FRACTION
	return clampf(profile.night_projectile_shading_fraction, 0.0, 1.0)

func _cleanup_vfx(vfx : VFXInstance) -> void:
	if vfx.canvas_item.is_valid():
		#critical: free the rid from the server to prevent memory leaks.
		RenderingServer.free_rid(vfx.canvas_item)
	_active_vfx.erase(vfx)

func apply_debug_visual_flags() -> void: ##clears currently drawn diagnostic-disabled visuals while leaving their gameplay resolvers alive
	if DebugAssistant.disable_vfx_visuals:
		_clear_active_vfx_draws()
		return

	if DebugAssistant.disable_projectile_visuals:
		RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)
		RenderingServer.canvas_item_clear(_projectile_chroma_canvas_item)
		_clear_projectile_texture_batches()
		for vfx: VFXInstance in _active_vfx:
			if vfx.is_projectile:
				_clear_vfx_draw(vfx)
	elif DebugAssistant.disable_projectile_trails:
		RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)

func _clear_active_vfx_draws() -> void:
	RenderingServer.canvas_item_clear(_projectile_trail_canvas_item)
	RenderingServer.canvas_item_clear(_projectile_chroma_canvas_item)
	_clear_projectile_texture_batches()
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
	vfx.projectile_chroma_strength = info.projectile_chroma_strength if is_projectile else 0.0
	vfx.projectile_trail_chroma_strength = info.projectile_trail_chroma_strength if is_projectile else 0.0

	if lifetime == INF: #NOTE: INF means to use info.lifetime
		vfx.lifetime = info.lifetime
	#to get a truly infinite-span projectile, use negative values (VFXInfo.INFINITE_LIFETIME)
	else:
		vfx.lifetime = lifetime

	if _can_use_projectile_texture_multimesh(info, is_projectile):
		vfx.uses_projectile_texture_multimesh = _get_projectile_texture_batch(info) != null

	if not vfx.uses_projectile_texture_multimesh:
		vfx.canvas_item = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(vfx.canvas_item, _get_vfx_canvas_parent(is_projectile))
		RenderingServer.canvas_item_set_z_index(vfx.canvas_item, vfx.vfx_info.graphical_layer)
		#attach our orphan canvas item to the correct render pass
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
		if node_vfx.has_meta(META_EXEMPT_PROJECTILE_VFX):
			node_vfx.position = position
		else:
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

	if not add_exempt_node(field, position):
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"vfx_suppressed")
		return null

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

	if not add_exempt_node(line, Vector2.ZERO):
		return null

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

	if not add_exempt_node(beam, Vector2.ZERO):
		return null

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

	if info.is_persistent and is_instance_valid(host) and not is_projectile:
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
		if is_projectile and is_instance_valid(_projectile_canvas_root):
			_projectile_canvas_root.add_child(instance)
			instance.set_meta(META_EXEMPT_PROJECTILE_VFX, true)
		elif is_instance_valid(Run.references.island):
			Run.references.island.add_child(instance)

	#contract
	instance.z_index = Layers.ALLIED_PROJECTILES
	instance.z_as_relative = false
	if instance.has_meta(META_EXEMPT_PROJECTILE_VFX):
		instance.position = pos
	else:
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
		var chroma_strength: float = info.projectile_chroma_strength if is_projectile else 0.0
		_register_scene_tint(instance as CanvasItem, lifetime, projectile_tints, projectile_tint_lifetime, is_projectile, chroma_strength)

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

func _register_scene_tint(
	canvas_item: CanvasItem,
	lifetime: float,
	projectile_tints: Array[Color],
	projectile_tint_lifetime: float,
	white_push_enabled: bool = false,
	chroma_strength: float = 0.0
) -> void: ##tracks scene-backed projectile visuals in the same tint-cycle system used by procedural projectile sprites
	for scene_tint: SceneTintState in _active_scene_tints:
		if scene_tint.canvas_item != canvas_item:
			continue

		scene_tint.base_modulate = canvas_item.modulate
		scene_tint.projectile_tints = projectile_tints.duplicate()
		scene_tint.lifetime = lifetime
		scene_tint.tint_cycle_lifetime = projectile_tint_lifetime
		scene_tint.white_push_enabled = white_push_enabled
		scene_tint.chroma_strength = chroma_strength
		scene_tint.age = 0.0
		return

	var scene_tint := SceneTintState.new()
	scene_tint.canvas_item = canvas_item
	scene_tint.base_modulate = canvas_item.modulate
	scene_tint.projectile_tints = projectile_tints.duplicate()
	scene_tint.lifetime = lifetime
	scene_tint.tint_cycle_lifetime = projectile_tint_lifetime
	scene_tint.white_push_enabled = white_push_enabled
	scene_tint.chroma_strength = chroma_strength
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
