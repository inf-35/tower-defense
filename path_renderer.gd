extends Node2D
class_name PathRenderer

@export var stroke_texture: Texture2D ## The main brush stroke (straight lines)
@export var corner_texture: Texture2D ## The stamp for 90 degree turns

@export var tint_color: Color = Color(1,1,1,0.6)
@export var stroke_spacing: float = 5.0 ## Distance between stamps on straight lines
@export var stroke_scale: Vector2 = Vector2(0.1, 0.1)

@export var line_color: Color = Color(0.2, 0.15, 0.1, 0.8) # Standard Path
@export var phasing_color: Color = Color(0.92, 0.0, 0.015, 0.8) # Wall-ignoring Path
@export var blocked_color: Color = Color(1.0, 0.2, 0.2, 0.8) # Invalid Path

@export var pos_jitter: float = 0.5 ## Random offset in pixels
@export var rot_jitter: float = 5.0 ## Random rotation in degrees
@export var scale_jitter: float = 0.0 ## Random scale variation (e.g. 0.1 = +/- 10%)

@export var wave_frequency: float = 0.8
@export var wave_min_alpha: float = 0.4
@export var flow_speed: float = 1.0
var _time_accumulator: float

var _time_from_last_step: float = 0.0
const _TIMESTEP: float = 0.2

class PathRender:
	var points: PackedVector2Array
	var is_phasing: bool
	var is_valid: bool = true

var _path_cache: Array[PathRender]
var _preview_path_cache: Array[PathRender]
var _is_previewing: bool = false
var _is_preview_blocked: bool = false


func _ready() -> void:
	scale = Vector2.ONE
	
	var island: Island = get_parent() as Island
	if is_instance_valid(island):
		island.navigation_grid_updated.connect(_on_navigation_grid_updated)
	
	Navigation.field_ready.connect(func(_goal, _ignore): _on_navigation_grid_updated())
	_on_navigation_grid_updated()
	
func _process(_d: float) -> void:
	_time_from_last_step += Clock.game_delta
	_time_accumulator += Clock.game_delta
	
	if _time_from_last_step > _TIMESTEP:
		queue_redraw()
		_time_from_last_step = 0.0

func update_preview(blocker_cells: Array[Vector2i]) -> void:
	_is_previewing = true
	_preview_path_cache.clear()
	_is_preview_blocked = false
	
	var modes = _get_current_wave_modes()
	
	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	var target_cell: Vector2i = Vector2i.ZERO
	
	for start_cell: Vector2i in spawn_points:
		if modes.normal:
			var path_render: PathRender = _generate_path_render(start_cell, blocker_cells, false, true)
			_preview_path_cache.append(path_render)
		
		if modes.phasing:
			var path_render: PathRender = _generate_path_render(start_cell, blocker_cells, true, true)
			_preview_path_cache.append(path_render)
	queue_redraw()

func clear_preview() -> void:
	_is_previewing = false
	_preview_path_cache.clear()
	queue_redraw()

func _on_navigation_grid_updated() -> void:
	await get_tree().process_frame
	_path_cache.clear()

	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	var modes = _get_current_wave_modes()
	
	for start_cell: Vector2i in spawn_points:
		if modes.normal:
			var data = _generate_path_render(start_cell, [], false, false)
			if data.is_valid: _path_cache.append(data)
			
		if modes.phasing:
			var data = _generate_path_render(start_cell, [], true, false)
			if data.is_valid: _path_cache.append(data)
	
	queue_redraw()

# --- Internal Helpers ---

func _get_current_wave_modes() -> Dictionary:
	var modes = { "normal": false, "phasing": false }
	
	# If outside combat/setup, default to normal
	if Phases.current_wave_number <= 0:
		modes.normal = true
		return modes
		
	var enemies = WaveEnemies.get_enemies_for_wave(Phases.current_wave_number)
	
	if enemies.is_empty():
		modes.normal = true
		return modes
		
	for stack in enemies:
		var type = stack[0]
		# Explicit check for known phasing unit types
		if type == Units.Type.TROLL or type == Units.Type.PHANTOM:
			modes.phasing = true
		else:
			modes.normal = true
	return modes
			
func _generate_path_render(start: Vector2i, blockers: Array[Vector2i], ignore_walls: bool, is_hypothetical: bool) -> PathRender:
	var goal = Vector2i.ZERO
	var result = PathRender.new()
	result.is_phasing = ignore_walls
	
	var path_struct: Navigation.PathData
	
	if is_hypothetical:
		path_struct = Navigation.get_hypothetical_path(start, goal, blockers, ignore_walls)
	else:
		path_struct = Navigation.find_path(start, goal, ignore_walls)
		
	if path_struct.status == Navigation.PathData.Status.FOUND_PATH:
		result.points = _convert_path_to_world(start, path_struct.path)
		result.is_valid = true
	else:
		result.points = []
		result.is_valid = false
		
	return result

func _convert_path_to_world(start: Vector2i, path_cells: Array[Vector2i]) -> PackedVector2Array:
	var world_points := PackedVector2Array([Island.cell_to_position(start)])
	for cell: Vector2i in path_cells:
		world_points.append(Island.cell_to_position(cell))
	return world_points

func _draw() -> void:
	var list_to_draw = _preview_path_cache if _is_previewing else _path_cache
	# Determine color

	for data: PathRender in list_to_draw:
		if data.points.size() <= 1: continue
		
		var draw_color: Color = phasing_color if data.is_phasing else line_color
		if not data.is_valid:
			# Only show blocked paths if we are previewing
			if _is_previewing:
				draw_color = blocked_color
			else:
				continue
		else:
			draw_color = phasing_color if data.is_phasing else line_color
			
		# Adjust opacity for overlap
		draw_color.a = draw_color.a / max(1, list_to_draw.size() * 0.5)
		if data.is_phasing: draw_color.a *= 3.0
		_draw_stamped_path(data.points, draw_color)

# --- Stamping Logic ---

func _draw_stamped_path(points: PackedVector2Array, color: Color) -> void:
	if not stroke_texture: return

	# Seed based on start position so the "hand drawn" look doesn't jitter every frame
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(points[0])
	
	var path_dist_traveled: float = 0.0

	for i in points.size():
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
					
		var stroke_color := color
		stroke_color.a *= _calculate_path_alpha(path_dist_traveled)
		# 3. Draw Node Stamp (Corner)
		if is_corner and corner_texture:
			# Calculate angle: Bisect the angle for the corner stamp? 
			# Or just align to the incoming direction?
			# Simple approach: Align to incoming, let texture handle the look.
			_draw_single_stamp(current_pos, dir_prev.angle(), corner_texture, stroke_color, rng, flip_corner)
		
		# 4. Draw Segment Strokes (Connecting to next point)
		elif i < points.size() - 1:
			_draw_single_stamp(current_pos, dir_next.angle(), stroke_texture, stroke_color, rng, false)
		
		path_dist_traveled += 1.0

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

func _calculate_path_alpha(distance: float) -> float:
	var wave_phase: float = (distance * wave_frequency) - (_time_accumulator * flow_speed)
	var sin_val = (sin(wave_phase) + 1.0) * 0.5
	return lerp(wave_min_alpha, 1.0, sin_val)
