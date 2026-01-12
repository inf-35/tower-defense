extends Node
#VFXManager. Bypasses the scene tree and calls the renderingserver directly
var _active_vfx: Array[VFXInstance] = []
#a flat array allows for optimal memory access

func _ready():
	# We draw our effects ourselves during the frame_post_draw signal.
	RenderingServer.frame_post_draw.connect(_draw_vfx)

func _process(_d: float):
	var delta: float = Clock.game_delta
	if _active_vfx.is_empty():
		return
		
	if delta == 0.0: #the game is paused, probably
		return
	
	var vfx_to_remove : Array[VFXInstance] = []
	# --- Update the state of all active effects ---
	for vfx : VFXInstance in _active_vfx:
		# Update lifetime
		vfx.age += delta
		if vfx.age >= vfx.lifetime and vfx.lifetime > 0.0:
			vfx.delete = true
		if vfx.delete:
			vfx_to_remove.append(vfx)
			continue
			
		# Update position and rotation
		vfx.position += vfx.velocity * delta
		match vfx.vfx_info.rotation_mode:
			VFXInfo.RotationMode.FACE_VELOCITY when not vfx.velocity.is_zero_approx():
				vfx.rotation = vfx.velocity.angle()
			VFXInfo.RotationMode.SPIN:
				vfx.rotation += vfx.vfx_info.spin_speed * delta
	
	for vfx : VFXInstance in vfx_to_remove: #deferred cleanup
		_cleanup_vfx(vfx)

func _draw_vfx():
	for vfx : VFXInstance in _active_vfx:
		var info : VFXInfo = vfx.vfx_info
		var normalized_lifetime : float = vfx.age / info.lifetime
		var canvas_item_rid : RID = vfx.canvas_item

		# --- Calculate common properties ---
		var current_scale_val = 1.0 if not info.scale_over_lifetime else info.scale_over_lifetime.sample(normalized_lifetime)
		current_scale_val *= info.scale
		var current_color = Color.WHITE if not info.color_over_lifetime else info.color_over_lifetime.sample(normalized_lifetime)
		var transform := Transform2D(vfx.rotation, Vector2.ZERO).scaled(Vector2(current_scale_val, current_scale_val))
		transform = transform.translated(vfx.position)
		
		# CRITICAL: We must clear the canvas item before drawing the new frame.
		RenderingServer.canvas_item_clear(canvas_item_rid)
		
		# Apply the transform and color globally for this item
		RenderingServer.canvas_item_set_transform(canvas_item_rid, transform)
		RenderingServer.canvas_item_set_modulate(canvas_item_rid, current_color)
		
		# --- Call the correct RenderingServer function based on type ---
		match info.vfx_type:
			VFXInfo.VFXType.TEXTURE:
				if not is_instance_valid(info.texture):
					return #abort
				transform = transform.scaled(Vector2.ONE * current_scale_val)
				
				var frame := int(vfx.age * info.fps) % (info.h_frames * info.v_frames)
				var fx : int = frame % info.h_frames
				@warning_ignore_start("integer_division")
				var fy : int = frame / info.h_frames
				var region_w = info.texture.get_width() / info.h_frames
				var region_h = info.texture.get_height() / info.v_frames
				var region : Rect2 = Rect2(fx * region_w, fy * region_h, region_w, region_h)
				var draw_rect := Rect2(-region.size * 0.5, region.size)
				RenderingServer.canvas_item_add_texture_rect_region(canvas_item_rid, draw_rect, info.texture.get_rid(), region)

			VFXInfo.VFXType.CIRCLE:
				var radius : float = info.radius * current_scale_val
				# For primitives, position is handled by the transform, not the primitive's offset.)
				RenderingServer.canvas_item_add_circle(canvas_item_rid, Vector2.ZERO, radius, current_color)

			VFXInfo.VFXType.RECTANGLE:
				var size : Vector2 = info.size * current_scale_val
				var rect := Rect2(-size / 2.0, size)
				RenderingServer.canvas_item_set_transform(canvas_item_rid, transform)
				if info.filled:
					RenderingServer.canvas_item_add_rect(canvas_item_rid, rect, current_color)
				else:
					var corners : PackedVector2Array = [
						rect.position,
						Vector2(rect.position.x + rect.size.x, rect.position.y),
						rect.position + rect.size,
						Vector2(rect.position.x, rect.position.y + rect.size.y)
					]
					RenderingServer.canvas_item_add_polyline(canvas_item_rid, corners, current_color, info.primitive_width)

func _cleanup_vfx(vfx : VFXInstance):
	# CRITICAL: Free the RID from the server to prevent memory leaks.
	RenderingServer.free_rid(vfx.canvas_item)
	_active_vfx.erase(vfx)

#public api
func play_vfx(info: VFXInfo, position: Vector2, velocity: Vector2 = Vector2.ZERO, lifetime: float = INF) -> VFXInstance:
	if not info: return

	var vfx := VFXInstance.new()
	vfx.vfx_info = info
	vfx.position = position
	vfx.velocity = velocity
	
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
