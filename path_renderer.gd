extends Node2D
class_name PathRenderer

# --- Configuration ---
@export_group("Assets")
@export var stroke_texture: Texture2D ## The main brush stroke (straight lines)
@export var corner_texture: Texture2D ## The stamp for 90 degree turns

@export_group("Style")
@export var tint_color: Color = Color(1,1,1,0.6)
@export var stroke_spacing: float = 5.0 ## Distance between stamps on straight lines
@export var stroke_scale: Vector2 = Vector2(0.1, 0.1)

@export_subgroup("Jitter")
@export var pos_jitter: float = 0.5 ## Random offset in pixels
@export var rot_jitter: float = 5.0 ## Random rotation in degrees
@export var scale_jitter: float = 0.0 ## Random scale variation (e.g. 0.1 = +/- 10%)

var _path_cache: Dictionary[Vector2i, PackedVector2Array] = {}
var _preview_path_cache: Dictionary[Vector2i, PackedVector2Array] = {}
var _is_previewing: bool = false
var _is_preview_blocked: bool = false

func _ready() -> void:
	scale = Vector2.ONE
	
	var island: Island = get_parent() as Island
	if is_instance_valid(island):
		island.navigation_grid_updated.connect(_on_navigation_grid_updated)
	
	Navigation.field_ready.connect(func(_goal, _ignore): _on_navigation_grid_updated())
	_on_navigation_grid_updated()

# --- Public API (Unchanged) ---

func update_preview(blocker_cells: Array[Vector2i]) -> void:
	_is_previewing = true
	_preview_path_cache.clear()
	_is_preview_blocked = false
	
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	var target_cell: Vector2i = Vector2i.ZERO
	
	for start_cell: Vector2i in spawn_points:
		var path_data := Navigation.get_hypothetical_path(start_cell, target_cell, blocker_cells, false)
		if path_data.status == Navigation.PathData.Status.FOUND_PATH:
			_preview_path_cache[start_cell] = _convert_path_to_world(start_cell, path_data.path)
		else:
			_is_preview_blocked = true
			
	queue_redraw()

func clear_preview() -> void:
	_is_previewing = false
	_preview_path_cache.clear()
	queue_redraw()

func _on_navigation_grid_updated() -> void:
	await get_tree().create_timer(0.2).timeout
	_path_cache.clear()

	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	var target_cell: Vector2i = Vector2i.ZERO
	
	for start_cell: Vector2i in spawn_points:
		var path_data: Navigation.PathData = Navigation.find_path(start_cell, target_cell, false)
		if path_data.status == Navigation.PathData.Status.FOUND_PATH:
			_path_cache[start_cell] = _convert_path_to_world(start_cell, path_data.path)
	
	queue_redraw()

# --- Internal Helpers ---

func _convert_path_to_world(start: Vector2i, path_cells: Array[Vector2i]) -> PackedVector2Array:
	var world_points := PackedVector2Array([Island.cell_to_position(start)])
	for cell: Vector2i in path_cells:
		world_points.append(Island.cell_to_position(cell))
	return world_points

func _draw() -> void:
	var cache_to_draw: Dictionary = _preview_path_cache if _is_previewing else _path_cache
	
	# Determine color
	var draw_color: Color = tint_color
	
	# Adjust opacity for overlap
	draw_color.a = draw_color.a / max(1, cache_to_draw.size() * 0.5)

	for start_cell: Vector2i in cache_to_draw:
		var points: PackedVector2Array = cache_to_draw[start_cell]
		if points.size() > 1:
			_draw_stamped_path(points, draw_color)

# --- Stamping Logic ---

func _draw_stamped_path(points: PackedVector2Array, color: Color) -> void:
	if not stroke_texture: return

	# Seed based on start position so the "hand drawn" look doesn't jitter every frame
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(points[0])

	for i in range(points.size()):
		var current_pos = points[i]
		
		# 1. Determine Directions
		var dir_prev = Vector2.ZERO
		var dir_next = Vector2.ZERO
		
		if i > 0: 
			dir_prev = (current_pos - points[i-1]).normalized()
		if i < points.size() - 1:
			dir_next = (points[i+1] - current_pos).normalized()
			
		# 2. Check for Corner
		# If the direction in is different from direction out, we are at a bend.
		# We use a dot product check (if dot < 0.9, they aren't parallel)
		var is_corner: bool = false
		var flip_corner: bool = true
		if i > 0 and i < points.size() - 1:
			if dir_prev.dot(dir_next) < 0.9:
				is_corner = true
				# NEW: Determine Turn Direction via Cross Product
				# In Godot (Y-Down), cross product (x1*y2 - x2*y1) gives:
				# > 0: Right Turn (Clockwise)
				# < 0: Left Turn (Counter-Clockwise)
				var cross = dir_prev.cross(dir_next)
				if cross < 0:
					flip_corner = false
					
		
		# 3. Draw Node Stamp (Corner)
		if is_corner and corner_texture:
			# Calculate angle: Bisect the angle for the corner stamp? 
			# Or just align to the incoming direction?
			# Simple approach: Align to incoming, let texture handle the look.
			_draw_single_stamp(current_pos, dir_prev.angle(), corner_texture, color, rng, flip_corner)
		
		# 4. Draw Segment Strokes (Connecting to next point)
		elif i < points.size() - 1:
			_draw_single_stamp(current_pos, dir_next.angle(), stroke_texture, color, rng, false)

func _draw_single_stamp(pos: Vector2, angle: float, tex: Texture2D, color: Color, rng: RandomNumberGenerator, flip_y: bool) -> void:
	# Jitter calculations
	var pos_offset = Vector2(rng.randf_range(-pos_jitter, pos_jitter), rng.randf_range(-pos_jitter, pos_jitter))
	var rot_offset = deg_to_rad(rng.randf_range(-rot_jitter, rot_jitter))
	var s_jitter = rng.randf_range(-scale_jitter, scale_jitter)
	
	var final_pos = pos + pos_offset
	var final_rot = angle + rot_offset
	var final_scale = stroke_scale * (1.0 + s_jitter)
	
	if flip_y:
		final_scale.y *= -1.0
	
	# Drawing with Transform
	# We construct a transform to handle the rotation and positioning
	var xform = Transform2D(final_rot, Vector2.ZERO)
	xform = xform.translated(final_pos)

	var tex_size = tex.get_size() * final_scale
	var rect := Rect2(-tex_size * 0.5, tex_size)
	
	draw_set_transform_matrix(xform)
	draw_texture_rect(tex, rect, false, color)
	#
	## Reset transform for next operations (though we reset it every loop iteration anyway)
	#draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
