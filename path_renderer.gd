extends Node2D
class_name PathRenderer

@export var stroke_texture: Texture2D ##the main brush stroke (straight lines)
@export var corner_texture: Texture2D ##the stamp for 90 degree turns
@export var obstruction_warning_renderer: ObstructionWarningRenderer ##single-canvas renderer for tower cells crossed by active routes
@export var path_wash_layer: PathWashLayer ##low-z watercolor surface for ordinary enemy routes

@export var stroke_scale: Vector2 = Vector2(0.1, 0.1) ##world-space scale applied to straight and corner route stamps

@export var line_color: Color = Color(0.68, 0.52, 0.19, 0.42) ##ink tint for standard direct-to-keep routes
@export var raider_color: Color = Color(0.88, 0.45, 0.12, 0.82) ##ink tint for settlement-raiding routes
@export var phasing_color: Color = Color(0.92, 0.0, 0.015, 0.8) ##ink tint for wall-ignoring routes
@export var blocked_color: Color = Color(1.0, 0.2, 0.2, 0.8) ##ink tint reserved for invalid hypothetical routes

@export var pos_jitter: float = 0.5 ##random offset in pixels
@export var rot_jitter: float = 5.0 ##random rotation in degrees
@export var scale_jitter: float = 0.0 ##random scale variation (e.g. 0.1 = +/- 10%)

@export var wave_frequency: float = 0.8 ##opacity-wave frequency measured across successive route cells
@export var wave_min_alpha: float = 0.4 ##minimum route-stamp opacity at the trough of the traveling wave
@export var flow_speed: float = 1.0 ##game-time speed of the opacity wave moving toward the route goal
var _time_accumulator: float

var _time_from_last_step: float = 0.0
const _TIMESTEP: float = 0.2
const ROUTE_INDICATOR_OPACITY_REFERENCE_COUNT: float = 2.0
const ROUTE_INDICATOR_OPACITY_DENSITY_EXPONENT: float = 0.35
const ROUTE_INDICATOR_OPACITY_MIN_SCALE: float = 0.38

class PathRender:
	var start_cell: Vector2i ##breach where route begins
	var path_cells: Array[Vector2i] ##ordered navigation cells returned by route planner
	var path_cell_set: Dictionary[Vector2i, bool] ##path cells but as a lookup table
	var points: PackedVector2Array ##Array[Vector2], cells converted to worldspace centers
	var is_phasing: bool
	var route_mode: int ##direct-to-keep ro raider chain
	var is_valid: bool ##whether route is found

	func _init() -> void:
		path_cells = []
		path_cell_set = {}
		points = PackedVector2Array()
		is_phasing = false
		route_mode = NavigationComponent.RouteMode.DIRECT_TO_GOAL
		is_valid = true

var _path_cache: Array[PathRender] = []
var _path_cache_by_key: Dictionary = {}
var _path_cell_set: Dictionary[Vector2i, bool] = {}
var _preview_path_cache: Array[PathRender] = []
var _preview_blockers: Dictionary = {}
var _preview_blocker_hash: int = 0
var _is_previewing: bool = false
var _path_cache_dirty: bool = true
var _preview_dirty: bool = false
var _is_initialised: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	scale = Vector2.ONE
	if not Run.is_run_ready():
		await Run.references_ready
	_configure_environment_style()

	var island: Island = get_parent() as Island
	assert(island != null, "PathRenderer must be parented under an Island.")
	island.navigation_grid_updated.connect(_mark_paths_dirty)
	island.navigation_grid_soft_updated.connect(_mark_paths_dirty)
	Run.phases.wave_cycle_started.connect(_mark_paths_dirty)
	SpawnPointService.spawn_points_changed.connect(_mark_paths_dirty)
	_is_initialised = true
	_mark_paths_dirty()

func _configure_environment_style() -> void: ##loads ordinary-route ink and watercolor colors from the run's active environment profile
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return

	line_color = profile.path_indicator_color
	if is_instance_valid(path_wash_layer):
		path_wash_layer.configure_environment(profile)

func _process(_d: float) -> void:
	if not _is_initialised:
		return

	_time_from_last_step += Clock.game_delta
	_time_accumulator += Clock.game_delta

	var redrew: bool = false
	if _path_cache_dirty:
		_rebuild_committed_paths()
		_path_cache_dirty = false
		redrew = true

	if _is_previewing and _preview_dirty:
		_rebuild_preview_paths()
		_preview_dirty = false
		redrew = true

	if redrew:
		_refresh_obstruction_warnings()
		_refresh_path_wash()

	if redrew or _time_from_last_step > _TIMESTEP:
		queue_redraw()
		_time_from_last_step = 0.0

func update_preview(blocker_cells: Array[Vector2i]) -> void:
	var blocker_hash: int = _hash_blocker_cells(blocker_cells)
	if _is_previewing and blocker_hash == _preview_blocker_hash and not _preview_dirty:
		return

	_preview_blockers.clear()
	for cell: Vector2i in blocker_cells:
		_preview_blockers[cell] = true

	_preview_blocker_hash = blocker_hash
	_is_previewing = true
	_preview_dirty = true

func clear_preview() -> void:
	_is_previewing = false
	_preview_dirty = false
	_preview_blocker_hash = 0
	_preview_blockers.clear()
	_preview_path_cache.clear()
	_refresh_obstruction_warnings()
	_refresh_path_wash()
	queue_redraw()

func _mark_paths_dirty(_unused = null) -> void:
	_path_cache_dirty = true
	if _is_previewing:
		_preview_dirty = true

func _rebuild_committed_paths() -> void:
	_path_cache.clear()
	_path_cache_by_key.clear()
	_path_cell_set.clear()

	for breach: Tower in SpawnPointService.get_active_breaches():
		for variant: Dictionary in _get_current_wave_variants(breach):
			_store_committed_path(_build_path_render(breach.tower_position, bool(variant.ignore_walls), int(variant.route_mode)))

func _store_committed_path(path_render: PathRender) -> void:
	_path_cache_by_key[_make_path_key(path_render.start_cell, path_render.is_phasing, path_render.route_mode)] = path_render
	if path_render.is_valid:
		_path_cache.append(path_render)
		_path_cell_set[path_render.start_cell] = true
		for cell: Vector2i in path_render.path_cells:
			_path_cell_set[cell] = true

func is_path_cell(cell: Vector2i) -> bool: ##returns whether any currently committed enemy route occupies this tile
	return _path_cell_set.has(cell)

func _refresh_path_wash() -> void: ##publishes only valid non-phasing routes to the low-z watercolor presentation layer
	if not is_instance_valid(path_wash_layer):
		return

	var wash_paths: Array[PackedVector2Array] = []
	var seen_signatures: Dictionary[int, bool] = {}
	var active_paths: Array[PathRender] = _preview_path_cache if _is_previewing else _path_cache
	for path_render: PathRender in active_paths:
		if not path_render.is_valid or path_render.is_phasing or path_render.points.size() < 2:
			continue
		var signature: int = hash(path_render.points)
		if seen_signatures.has(signature):
			continue
		seen_signatures[signature] = true
		wash_paths.append(path_render.points)

	path_wash_layer.set_paths(wash_paths, _get_route_opacity_scale(wash_paths.size()))

func _get_route_opacity_scale(route_count: int) -> float: ##keeps the existing square-root density scale for the watercolor route wash
	return 1.0 / sqrt(maxf(1.0, float(route_count) * 0.5))

func _get_route_indicator_opacity_scale(route_count: int) -> float: ##softly compresses route density so low-weight dashed branches fade without disappearing
	var density: float = maxf(1.0, float(route_count))
	var opacity_scale: float = pow(ROUTE_INDICATOR_OPACITY_REFERENCE_COUNT / density, ROUTE_INDICATOR_OPACITY_DENSITY_EXPONENT)
	return maxf(opacity_scale, ROUTE_INDICATOR_OPACITY_MIN_SCALE)

func _refresh_obstruction_warnings() -> void: ##classifies route-obstructing cells by whether normal or only wall-ignoring enemies cross them
	if not is_instance_valid(obstruction_warning_renderer):
		return

	var primary_warning_cell_set: Dictionary[Vector2i, bool] = {}
	var intermediate_warning_cell_set: Dictionary[Vector2i, bool] = {}
	var active_paths: Array[PathRender] = _preview_path_cache if _is_previewing else _path_cache
	for path_render: PathRender in active_paths:
		if not path_render.is_valid:
			continue
		for cell: Vector2i in path_render.path_cells:
			if not _is_route_obstruction_cell(cell):
				continue

			if path_render.is_phasing:
				intermediate_warning_cell_set[cell] = true
			else:
				primary_warning_cell_set[cell] = true

	for cell: Vector2i in primary_warning_cell_set:
		intermediate_warning_cell_set.erase(cell)

	var primary_warning_cells: Array[Vector2i] = _get_sorted_cells(primary_warning_cell_set)
	var intermediate_warning_cells: Array[Vector2i] = _get_sorted_cells(intermediate_warning_cell_set)
	obstruction_warning_renderer.set_warning_cells(primary_warning_cells, intermediate_warning_cells)

func _is_route_obstruction_cell(cell: Vector2i) -> bool: ##tests preview blockers first, then the live tower's navigation-specific blocking rule
	if _is_previewing and _preview_blockers.has(cell):
		return true

	var tower: Tower = Run.references.island.get_tower_on_tile(cell)
	return is_instance_valid(tower) and tower.obstructs_navigation_at_cell(cell)

func _get_sorted_cells(cell_set: Dictionary[Vector2i, bool]) -> Array[Vector2i]: ##stabilizes renderer inputs so unchanged warning sets do not redraw
	var cells: Array[Vector2i] = []
	cells.assign(cell_set.keys())
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return cells

func _rebuild_preview_paths() -> void:
	_preview_path_cache.clear()

	for breach: Tower in SpawnPointService.get_active_breaches():
		for variant: Dictionary in _get_current_wave_variants(breach):
			_preview_path_cache.append(_build_preview_path_render(breach.tower_position, bool(variant.ignore_walls), int(variant.route_mode)))

func _build_preview_path_render(start_cell: Vector2i, ignore_walls: bool, route_mode: int) -> PathRender:
	var key: int = _make_path_key(start_cell, ignore_walls, route_mode)
	#assert(_path_cache_by_key.has(key), "Committed path cache missing preview source.")
	var committed_path: PathRender = _path_cache_by_key.get(key)

	if committed_path and (committed_path.is_phasing or not _intersects_blockers(committed_path)):
		return committed_path

	return _build_path_render(start_cell, ignore_walls, route_mode, _preview_blockers)

func _get_current_wave_variants(breach: Tower) -> Array[Dictionary]: ##keeps ordinary routes while restricting special navigation variants to enemies assigned to this breach
	var variants: Array[Dictionary] = []
	var seen_variant_keys: Dictionary[int, bool] = {}

	if Run.phases.current_wave_number <= 0:
		return [{"route_mode": NavigationComponent.RouteMode.DIRECT_TO_GOAL, "ignore_walls": false}]

	var enemies: Array[Array] = Run.waves.get_planned_enemies_for_wave(Run.phases.current_wave_number)
	if enemies.is_empty():
		return [{"route_mode": NavigationComponent.RouteMode.DIRECT_TO_GOAL, "ignore_walls": false}]

	var assigned_variant_keys: Dictionary[int, bool] = {}
	for stack: Array in Run.waves.get_planned_enemies_for_breach(breach):
		if int(stack[1]) <= 0:
			continue
		var unit_type: Units.Type = stack[0]
		var route_mode: int = Units.get_unit_route_mode(unit_type)
		var ignore_walls: bool = Units.get_unit_ignore_walls(unit_type)
		assigned_variant_keys[(route_mode << 1) | int(ignore_walls)] = true

	for stack: Array in enemies:
		if int(stack[1]) <= 0:
			continue
		var type: Units.Type = stack[0]
		var route_mode: int = Units.get_unit_route_mode(type)
		var ignore_walls: bool = Units.get_unit_ignore_walls(type)
		var variant_key: int = (route_mode << 1) | int(ignore_walls)
		if (ignore_walls or route_mode == NavigationComponent.RouteMode.RAIDER_CHAIN) and not assigned_variant_keys.has(variant_key):
			continue
		if seen_variant_keys.has(variant_key):
			continue
		seen_variant_keys[variant_key] = true
		variants.append({
			"route_mode": route_mode,
			"ignore_walls": ignore_walls,
		})

	return variants

func _build_path_render(start: Vector2i, ignore_walls: bool, route_mode: int, blockers: Dictionary = {}) -> PathRender:
	var result := PathRender.new()
	result.start_cell = start
	result.is_phasing = ignore_walls
	result.route_mode = route_mode

	var path_struct: Navigation.PathData
	if route_mode == NavigationComponent.RouteMode.RAIDER_CHAIN:
		var waypoint_cells: Array[Vector2i] = _get_raider_waypoints(start, ignore_walls)
		path_struct = RaiderRoutePlanner.build_path(start, waypoint_cells, ignore_walls, blockers)
	elif blockers.is_empty() or ignore_walls:
		path_struct = Navigation.find_path(start, Vector2i.ZERO, ignore_walls)
	else:
		path_struct = Navigation.get_hypothetical_path(start, Vector2i.ZERO, blockers, false)

	if path_struct.status != Navigation.PathData.Status.FOUND_PATH:
		result.is_valid = false
		return result

	result.path_cells = path_struct.path
	for cell: Vector2i in result.path_cells:
		result.path_cell_set[cell] = true
	result.points = _convert_path_to_world(start, result.path_cells)
	return result

func _intersects_blockers(path_render: PathRender) -> bool:
	for blocker: Vector2i in _preview_blockers:
		if path_render.path_cell_set.has(blocker):
			return true
	return false

func _convert_path_to_world(start: Vector2i, path_cells: Array[Vector2i]) -> PackedVector2Array:
	var world_points: PackedVector2Array = PackedVector2Array([Island.cell_to_position(start)])
	for cell: Vector2i in path_cells:
		world_points.append(Island.cell_to_position(cell))
	return world_points

func _make_path_key(start_cell: Vector2i, ignore_walls: bool, route_mode: int) -> int:
	var combined_coords: int = (int(start_cell.y) << 32) | (start_cell.x & 0xFFFFFFFF)
	return (combined_coords << 4) | (route_mode << 1) | int(ignore_walls)

func _get_raider_waypoints(start_cell: Vector2i, ignore_walls: bool) -> Array[Vector2i]:
	if Run.waves.current_combat_wave_number > 0:
		var frozen_waypoints: Array[Vector2i] = Run.waves.get_frozen_raider_waypoints(start_cell, ignore_walls)
		if not frozen_waypoints.is_empty():
			return frozen_waypoints

	return RaiderRoutePlanner.get_waypoint_cells_for_spawn(start_cell, Run.references.island.get_raid_targets())

func _hash_blocker_cells(blocker_cells: Array[Vector2i]) -> int:
	var hash_sum: int = 0
	var hash_xor: int = 0
	for cell: Vector2i in blocker_cells:
		var cell_hash: int = hash(cell)
		hash_sum += cell_hash
		hash_xor ^= cell_hash
	return hash([blocker_cells.size(), hash_sum, hash_xor])

func _draw() -> void:
	var list_to_draw = _preview_path_cache if _is_previewing else _path_cache

	for data: PathRender in list_to_draw:
		if data.points.size() <= 1:
			continue

		var draw_color: Color = line_color
		if not data.is_valid:
			if _is_previewing:
				draw_color = blocked_color
			else:
				continue
		else:
			if data.route_mode == NavigationComponent.RouteMode.RAIDER_CHAIN:
				draw_color = raider_color
			elif data.is_phasing:
				draw_color = phasing_color

		draw_color.a *= _get_route_indicator_opacity_scale(list_to_draw.size())
		if data.is_phasing and data.route_mode != NavigationComponent.RouteMode.RAIDER_CHAIN:
			draw_color.a *= 3.0
		_draw_stamped_path(data.points, draw_color)

#--- stamping logic ---

func _draw_stamped_path(points: PackedVector2Array, color: Color) -> void:
	if not stroke_texture: return

	#seed based on start position so the "hand drawn" look doesn't jitter every frame
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(points[0])

	var path_dist_traveled: float = 0.0

	for i in points.size():
		var current_pos = points[i]

		#1. determine directions
		var dir_prev = Vector2.ZERO
		var dir_next = Vector2.ZERO

		if i > 0:
			dir_prev = (current_pos - points[i-1]).normalized()
		if i < points.size() - 1:
			dir_next = (points[i+1] - current_pos).normalized()

		#2. check for corner
		#if the direction in is different from direction out, we are at a bend.
		#we use a dot product check (if dot < 0.9, they aren't parallel)
		var is_corner: bool = false
		var flip_corner: bool = true
		if i > 0 and i < points.size() - 1:
			if dir_prev.dot(dir_next) < 0.9:
				is_corner = true
				#new: determine turn direction via cross product
				#in godot (y-down), cross product (x1*y2 - x2*y1) gives:
				#> 0: right turn (clockwise)
				#< 0: left turn (counter-clockwise)
				var cross = dir_prev.cross(dir_next)
				if cross < 0:
					flip_corner = false

		var stroke_color := color
		stroke_color.a *= _calculate_path_alpha(path_dist_traveled)
		#3. draw node stamp (corner)
		if is_corner and corner_texture:
			#calculate angle: bisect the angle for the corner stamp?
			#or just align to the incoming direction?
			#simple approach: align to incoming, let texture handle the look.
			_draw_single_stamp(current_pos, dir_prev.angle(), corner_texture, stroke_color, rng, flip_corner)

		#4. draw segment strokes (connecting to next point)
		elif i < points.size() - 1:
			_draw_single_stamp(current_pos, dir_next.angle(), stroke_texture, stroke_color, rng, false)

		path_dist_traveled += 1.0

func _draw_single_stamp(pos: Vector2, angle: float, tex: Texture2D, color: Color, rng: RandomNumberGenerator, flip_y: bool) -> void:
	#jitter calculations
	var pos_offset: Vector2 = Vector2(rng.randf_range(-pos_jitter, pos_jitter), rng.randf_range(-pos_jitter, pos_jitter))
	var rot_offset = deg_to_rad(rng.randf_range(-rot_jitter, rot_jitter))
	var s_jitter = rng.randf_range(-scale_jitter, scale_jitter)

	var final_pos = pos + pos_offset
	var final_rot = angle + rot_offset
	var final_scale = stroke_scale * (1.0 + s_jitter)

	if flip_y:
		final_scale.y *= -1.0

	#drawing with transform
	#we construct a transform to handle the rotation and positioning
	var xform: Transform2D = Transform2D(final_rot, Vector2.ZERO)
	xform = xform.translated(final_pos)

	var tex_size = tex.get_size() * final_scale
	var rect: Rect2 = Rect2(-tex_size * 0.5, tex_size)

	draw_set_transform_matrix(xform)
	draw_texture_rect(tex, rect, false, color)


	##reset transform for next operations (though we reset it every loop iteration anyway)
	#draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _calculate_path_alpha(distance: float) -> float:
	var wave_phase: float = (distance * wave_frequency) - (_time_accumulator * flow_speed)
	var sin_val = (sin(wave_phase) + 1.0) * 0.5
	return lerp(wave_min_alpha, 1.0, sin_val)
