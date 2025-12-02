extends Node2D
class_name TerrainRenderer

# config
@export var shader: Shader
@export var cell_size: int = 10 # must match island cell_size
@export var max_gradient_depth: float = 5.0
@export var show_debug_texture: bool = false
@export var draw_background: bool = true

@export var background_stain_color: Color
@export var paint_color: Color
@export var wash_color: Color
@export var brush_textures: Array[Texture2D]

# references
var _brush_viewport: Viewport

# visual components
var _terrain_rect: ColorRect
var _bg_rect: ColorRect
var _bg_stain_rect: ColorRect
var _decoration_container: Node2D ## container for stamped sprites

var _grid_image: Image
var _grid_texture: ImageTexture
var _grid_data: Dictionary = {} # stores Vector2i -> bool (is_land)
# visual state trackers
var _active_decorations: Dictionary[Vector2i, Sprite2D] = {} # stores Vector2i -> Sprite2D
var _active_brush_strokes: Dictionary[Vector2i, Sprite2D]
# bounds management
# we track the top-left coordinate of the current image grid
var _min_coord: Vector2i = Vector2i.ZERO
var _size_cells: Vector2i = Vector2i(1, 1)

func _ready() -> void:
	_setup_visuals()
	
	if show_debug_texture:
		_create_debug_view()

func _create_debug_view() -> void:
	var dr = TextureRect.new()
	dr.texture = _grid_texture
	dr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dr.scale = Vector2(8, 8)
	dr.position = Vector2(20, 20)
	var c = CanvasLayer.new()
	c.add_child(dr)
	add_child(c)

func _setup_visuals() -> void:
	# initialize with a small empty grid
	_grid_image = Image.create(1, 1, false, Image.FORMAT_L8)
	_grid_texture = ImageTexture.create_from_image(_grid_image)
	
	_brush_viewport = SubViewport.new()
	_brush_viewport.name = "BrushMaskViewport"
	_brush_viewport.disable_3d = true
	_brush_viewport.transparent_bg = true
	_brush_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_brush_viewport)
	
	if draw_background:
		_bg_rect = ColorRect.new()
		_bg_rect.color = Color(1.0, 0.976, 0.941, 1.0)
		_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg_rect.size = Vector2(10000,10000)
		_bg_rect.position = Vector2(-5000,-5000)
		add_child(_bg_rect)

	_bg_stain_rect = ColorRect.new()
	_bg_stain_rect.name = "BackgroundStain"
	_bg_stain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var bg_stain_mat = ShaderMaterial.new()
	bg_stain_mat.shader = preload("res://Shaders/simple_mix_mask.gdshader")
	bg_stain_mat.set_shader_parameter("mask_texture", _brush_viewport.get_texture())
	bg_stain_mat.set_shader_parameter("tint_color", background_stain_color)
	_bg_stain_rect.material = bg_stain_mat
	add_child(_bg_stain_rect)
		
	_terrain_rect = ColorRect.new()
	_terrain_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	
	# noise setup
	var noise := FastNoiseLite.new()
	noise.frequency = 0.01
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.noise = noise
	noise_tex.seamless = true
	
	var watercolor_tex: NoiseTexture2D = noise_tex.duplicate_deep(Resource.DeepDuplicateMode.DEEP_DUPLICATE_ALL)
	watercolor_tex.noise.frequency = 0.005
	
	mat.set_shader_parameter("grid_data_texture", _grid_texture)
	mat.set_shader_parameter("distortion_texture", noise_tex)
	mat.set_shader_parameter("noise_texture", watercolor_tex)
	mat.set_shader_parameter("paint_color", paint_color)
	mat.set_shader_parameter("wash_color", wash_color)
	
	# placeholder paper (replace with load("res://...") if you have one)
	var paper_img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	paper_img.fill(Color(0.95, 0.95, 0.922, 1.0))
	var paper_tex = ImageTexture.create_from_image(paper_img)
	mat.set_shader_parameter("paper_texture", paper_tex)
	
	# pass the Viewport's texture to the shader
	# NOTE: viewport textures are dynamic and update with viewport contents
	mat.set_shader_parameter("brush_mask_texture", _brush_viewport.get_texture())
	
	_terrain_rect.material = mat
	_terrain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_terrain_rect)
	
	# decorations sit on top of the paint
	_decoration_container = Node2D.new()
	_decoration_container.name = "DecorationContainer"
	_decoration_container.y_sort_enabled = false # usually terrain stamps are flat, but set true if using upright trees
	add_child(_decoration_container)
	
	_update_rect_transform()

# --- public api ---

# accepts a list of tiles to add/remove to minimize resize operations
# changes: dictionary of { Vector2i cell: bool is_land }
func apply_terrain_changes(changes: Dictionary) -> void:
	if changes.is_empty():
		return
	var new_min := _min_coord
	var new_max := _min_coord + _size_cells - Vector2i.ONE
	
	# 1. update logic and calculate new bounds
	for cell: Vector2i in changes:
		var is_land: bool = changes[cell]
		
		if is_land:
			_grid_data[cell] = true
			# expand bounds if necessary
			if _grid_data.size() == 1: # first tile
				new_min = cell
				new_max = cell
			else:
				new_min.x = min(new_min.x, cell.x)
				new_min.y = min(new_min.y, cell.y)
				new_max.x = max(new_max.x, cell.x)
				new_max.y = max(new_max.y, cell.y)
			
			_spawn_brush_stroke(cell)
		else:
			_grid_data.erase(cell)
			# if a tile is removed, its decoration must also go
			if _active_decorations.has(cell):
				_active_decorations[cell].queue_free()
				_active_decorations.erase(cell)
			# NOTE: we don't shrink bounds automatically as it's expensive 
			# and islands usually grow. shrinking is optional optimization.

	# add padding to bounds for the gradient to fade out
	var padding = int(max_gradient_depth) + 2
	new_min -= Vector2i(padding, padding)
	new_max += Vector2i(padding, padding)
	
	# check if we need to resize image
	var current_max = _min_coord + _size_cells
	if new_min.x < _min_coord.x or new_min.y < _min_coord.y or new_max.x >= current_max.x or new_max.y >= current_max.y:
		_resize_grid(new_min, new_max - new_min + Vector2i.ONE)
	
	# 2. recalculate distance field
	_update_distance_field()
	
	_brush_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
# updates the stamped sprites on top of the blob
func update_decoration(cell: Vector2i, type: Terrain.Base) -> void:
	# 1. remove existing decoration at this cell
	if _active_decorations.has(cell):
		_active_decorations[cell].queue_free()
		_active_decorations.erase(cell)
	
	# 2. check if this terrain type has a visual icon
	var icon: Texture2D = Terrain.get_icon(type)
	if icon == null:
		return
		
	# 3. create the stamp
	var sprite := Sprite2D.new()
	sprite.texture = icon
	
	# calculate position: center of the cell + random offset
	var center_pos = (Vector2(cell) * cell_size) + (Vector2.ONE * cell_size * 0.5)
	sprite.position = center_pos
	# random rotation and scale for "hand-drawn" feel
	sprite.rotation_degrees = randf_range(-2, 2)
	var s = randf_range(0.9, 1.1)
	sprite.scale = Vector2(s, s) * 0.05
	
	# slight transparency to blend with the watercolor
	sprite.modulate.a = 1.0
	
	_decoration_container.add_child(sprite)
	_active_decorations[cell] = sprite

# completely clears and replaces the terrain with the new set of tiles
func reset_grid(new_land_tiles: Array[Vector2i]) -> void:
	# 1. reset data
	_grid_data.clear()
	# clear image (make it all water)
	_grid_image.fill(Color.BLACK)
	
	# 2. apply new tiles
	var active_cells: Dictionary = {}
	
	# if input is empty, just update texture and return
	if new_land_tiles.is_empty():
		_grid_texture.update(_grid_image)
		return
		
	# calculate new bounds
	var min_c := new_land_tiles[0]
	var max_c := new_land_tiles[0]
	
	for cell in new_land_tiles:
		_grid_data[cell] = true
		active_cells[cell] = true
		
		min_c.x = min(min_c.x, cell.x)
		min_c.y = min(min_c.y, cell.y)
		max_c.x = max(max_c.x, cell.x)
		max_c.y = max(max_c.y, cell.y)
		
	# 3. resize logic (similar to apply_terrain_changes)
	var padding = int(max_gradient_depth) + 2
	min_c -= Vector2i(padding, padding)
	max_c += Vector2i(padding, padding)
	var new_size = max_c - min_c + Vector2i.ONE
	
	_resize_grid(min_c, new_size)
	
	# 4. update visual (recalculate distance field for the new set)
	_update_distance_field()
	
# helper to modify shader parameters dynamically
func set_color_param(param_name: String, value: Color) -> void:
	(_terrain_rect.material as ShaderMaterial).set_shader_parameter(param_name, value)

# --- internal logic ---
func _spawn_brush_stroke(cell: Vector2i) -> void:
	if _active_brush_strokes.has(cell):
		return
	
	var brush_tex: Texture2D = brush_textures.pick_random()
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = brush_tex
	
	# Calculate Position
	# Important: Viewport coordinates are local to the viewport (0,0 is top left)
	# The TerrainRect also draws from 0,0 locally.
	# We need to map the global grid coordinates to this local space.
	var cell_center: Vector2 = (Vector2(cell) * cell_size) + (Vector2.ONE * cell_size * 0.5)
	
	# Since the Viewport moves WITH the grid logic (via _update_rect_transform logic below),
	# we can just set positions relative to the grid origin if we structure it right.
	# HOWEVER, simplest way: The Viewport covers the exact same rect as _terrain_rect.
	# so coordinates should be relative to _min_coord.
	
	var local_pos: Vector2 = cell_center - Vector2(_min_coord * cell_size)
	
	# store the sprite to update its position later if we shift the grid
	sprite.position = local_pos
	# randomisation
	sprite.rotation = randf() * TAU
	sprite.modulate = Color(1,1,1, randf_range(0.5, 1.0))
	var s: float = (randf_range(0.5, 1.0) ** 2) * 0.2
	sprite.scale = Vector2(s, s)
	
	_brush_viewport.add_child(sprite)
	_active_brush_strokes[cell] = sprite

func _resize_grid(new_origin: Vector2i, new_size: Vector2i) -> void:
	# safeguard against massive accidental sizes
	if new_size.x > 4096 or new_size.y > 4096:
		push_warning("terrain grid growing very large: ", new_size)
	
	# create new blank image
	var new_img = Image.create(new_size.x, new_size.y, false, Image.FORMAT_L8)
	
	# update state
	_grid_image = new_img
	_min_coord = new_origin
	_size_cells = new_size
	
	# update visual rect
	_update_rect_transform()

func _update_rect_transform() -> void:
	# place the rect in the world
	_terrain_rect.position = Vector2(_min_coord * cell_size)
	_terrain_rect.size = Vector2(_size_cells * cell_size)
	
	var MARGIN: float = _terrain_rect.size.x + 5.0
	_bg_stain_rect.position = _terrain_rect.position - Vector2.ONE * MARGIN
	_bg_stain_rect.size = _terrain_rect.size + Vector2.ONE * MARGIN * 2

	#adjust brush viewport size
	if _brush_viewport.size != Vector2i(_terrain_rect.size):
		_brush_viewport.size = Vector2i(_terrain_rect.size)
		
	# when _min_coord changes, the "local" position of existing brushes shifts.
	# we need to re-align existing brushes.
	for cell: Vector2i in _active_brush_strokes:
		var sprite: Sprite2D = _active_brush_strokes[cell]
		var cell_center_world = (Vector2(cell) * cell_size) + (Vector2.ONE * cell_size * 0.5)
		var local_pos = cell_center_world - _terrain_rect.position
		sprite.position = local_pos
	_brush_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	
	# pass world info to shader
	var mat = _terrain_rect.material as ShaderMaterial
	mat.set_shader_parameter("region_pixel_offset", _terrain_rect.position)
	mat.set_shader_parameter("region_pixel_size", _terrain_rect.size)

func _update_distance_field() -> void:
	# standard bfs logic, but offset by _min_coord
	_grid_image.fill(Color.BLACK) # clear image
	
	var dist_map := {} # local coords -> distance
	var queue: Array[Vector2i] = []
	
	# initialize bfs seeds (land tiles)
	# we do multi-source bfs from land outwards? 
	# actually for watercolor gradient usually we want dist FROM water INTO land.
	# so water is 0, land starts at 1.
	
	# simpler approach: fill image with 0. 
	# set all land pixels to -1 (unvisited).
	# find all land pixels next to water -> queue.
	
	# 1. map global _grid_data to local image pixels
	for global_pos in _grid_data:
		var local_pos = global_pos - _min_coord
		if local_pos.x >= 0 and local_pos.y >= 0 and local_pos.x < _size_cells.x and local_pos.y < _size_cells.y:
			# temporary marker for land
			_grid_image.set_pixelv(local_pos, Color(1, 1, 1, 1)) 
			
	# 2. build bfs for gradient
	# this is computationally heavy for huge maps.
	# optimization: only iterate pixels inside the dirty rect?
	# for now, we do full rebuild for correctness.
	
	var local_queue: Array[Vector2i] = []
	var visited := {}
	
	# find boundary: land cells adjacent to empty/water
	# since _grid_image is padded, we can iterate internal area
	for x in range(1, _size_cells.x - 1):
		for y in range(1, _size_cells.y - 1):
			if _grid_image.get_pixel(x, y).r > 0.5: # is land
				var is_coast = false
				# check 4 neighbors for water (black)
				if _grid_image.get_pixel(x+1, y).r < 0.5: is_coast = true
				elif _grid_image.get_pixel(x-1, y).r < 0.5: is_coast = true
				elif _grid_image.get_pixel(x, y+1).r < 0.5: is_coast = true
				elif _grid_image.get_pixel(x, y-1).r < 0.5: is_coast = true
				
				if is_coast:
					local_queue.append(Vector2i(x, y))
					visited[Vector2i(x, y)] = 1.0 # distance 1
	
	# bfs
	var head = 0
	while head < local_queue.size():
		var curr = local_queue[head]
		head += 1
		var dist = visited[curr]
			
		var neighbors = [Vector2i(0,1), Vector2i(0,-1), Vector2i(1,0), Vector2i(-1,0)]
		for n in neighbors:
			var next = curr + n
			# if it is land and we haven't assigned a distance yet
			# check bounds
			if next.x >= 0 and next.y >= 0 and next.x < _size_cells.x and next.y < _size_cells.y:
				# check if it is land (we marked land as white earlier)
				# and not visited (visited dict check)
				if _grid_image.get_pixelv(next).r > 0.5 and not visited.has(next):
					visited[next] = dist + 1.0
					local_queue.append(next)
	
	# 3. write final values to image
	# we need to clear the simple boolean mask we made in step 1 and replace with gradient
	_grid_image.fill(Color.BLACK)
	
	for local_pos in visited:
		var d = visited[local_pos]
		var norm = d / max_gradient_depth
		norm = clamp(norm, 0.0, 1.0)
		_grid_image.set_pixelv(local_pos, Color(norm, norm, norm))
		
	_grid_texture.set_image(_grid_image)
