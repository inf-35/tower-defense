extends Node
#VFXManager. Bypasses the scene tree and calls the renderingserver directly
var _active_vfx: Array[VFXInstance] = []
#a flat array allows for optimal memory access

func _ready() -> void:
	#we draw our effects ourselves during the frame_post_draw signal.
	RenderingServer.frame_post_draw.connect(_draw_vfx)

func _process(_d: float) -> void:
	var delta: float = Clock.game_delta
	if _active_vfx.is_empty():
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

		#update position and rotation
		vfx.position += vfx.velocity * delta
		match vfx.vfx_info.rotation_mode:
			VFXInfo.RotationMode.FACE_VELOCITY when not vfx.velocity.is_zero_approx():
				vfx.rotation = vfx.velocity.angle()
			VFXInfo.RotationMode.SPIN:
				vfx.rotation += vfx.vfx_info.spin_speed * delta

	for vfx : VFXInstance in vfx_to_remove: #deferred cleanup
		_cleanup_vfx(vfx)

func _draw_vfx() -> void:
	for vfx : VFXInstance in _active_vfx:
		var info: VFXInfo = vfx.vfx_info
		var normalized_lifetime: float = vfx.age / info.lifetime
		var canvas_item_rid: RID = vfx.canvas_item

		#--- calculate common properties ---
		var current_scale_val = 1.0 if not info.scale_over_lifetime else info.scale_over_lifetime.sample(normalized_lifetime)
		current_scale_val *= info.scale
		var current_color = Color.WHITE if not info.color_over_lifetime else info.color_over_lifetime.sample(normalized_lifetime)
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
				transform = transform.scaled(vfx.scale * current_scale_val)

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

func _cleanup_vfx(vfx : VFXInstance) -> void:
	#critical: free the rid from the server to prevent memory leaks.
	RenderingServer.free_rid(vfx.canvas_item)
	_active_vfx.erase(vfx)

#public api
func play_vfx(info: VFXInfo, position: Vector2, velocity: Vector2 = Vector2.ZERO, lifetime: float = INF, scale = Vector2.ONE, host: Node2D = null) -> Variant: ##returns either vfxinstance or instantiated node, dependent on whether vfx was a scene
	if not info: return

	if info.is_scene:
		return _play_vfx_scene(info, position, velocity, scale, host)
	var vfx := VFXInstance.new()
	vfx.vfx_info = info
	vfx.position = position
	vfx.velocity = velocity
	vfx.scale = scale * 0.06

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
	return vfx

func play_aoe_field(info: VFXInfo, position: Vector2, radius: float, cone_angle_deg: float = 360.0, aim_direction: Vector2 = Vector2.RIGHT) -> AoeParticleFieldVFX: ##spawns a dense marker field for circular or cone aoes using the per-resource authored particle settings
	if not info or not info.aoe_particles_enabled:
		return null

	if radius <= 0.0 or not is_instance_valid(info.aoe_particle_texture):
		return null

	var field := AoeParticleFieldVFX.new()

	var parent: Node = Run.references.projectiles if is_instance_valid(Run.references.projectiles) else Run.references.island
	if not is_instance_valid(parent):
		parent = self

	parent.add_child(field)
	field.global_position = position
	field.setup_from_info(info, radius, cone_angle_deg, aim_direction)
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

func create_swirl_beam_info(info: VFXInfo, start_position: Vector2, end_position: Vector2) -> SwirlLineVFX: ##spawns a persistent swirl beam from one authored resource so linked supports stay data-driven
	if not is_instance_valid(info):
		return null

	var beam: SwirlLineVFX = create_swirl_beam(
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
	if is_instance_valid(beam):
		beam.set_texture(info.swirl_particle_texture)
	return beam

func _play_vfx_scene(info: VFXInfo, pos: Vector2, velocity: Vector2, scale: Vector2, host: Node2D) -> Node2D:
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

	if instance.has_method("reset"):
		instance.reset()
	else:
		push_warning("VFX: ", instance, " lacks reset!")
	if instance.has_method("start"):
		instance.start()
	else:
		push_warning("VFX: ", instance, " lacks start!")

	return instance
