extends Node2D
class_name TerrainRenderer

@export var is_main_terrain_renderer: bool = false
#config
@export var max_gradient_depth: float = 5.0
@export var show_debug_texture: bool = false
@export var apply_environment_material_overrides: bool = false ##allows environment-profile paint values to replace the authored terrain material when explicitly enabled

@export var brush_textures: Array[Texture2D]

@export_group("Surfaces")
@export var terrain_rect: ColorRect ##authored shader surface receiving generated terrain textures and runtime bounds
@export var background_stain_rect: ColorRect ##authored brush-mask surface resized around the terrain bounds
@export var decoration_container: Node2D ##authored world-space parent for terrain stamps and placement previews
@export var paper_rect: TextureRect
@export var paper_grain_rect: TextureRect
@export var color_rect: ColorRect
@export_group("")

var cell_size: float = Island.CELL_SIZE

#references
var _brush_viewport: Viewport

var _grid_image: Image
var _grid_texture: ImageTexture
var _terrain_color_image: Image
var _terrain_color_texture: ImageTexture
var _terrain_wash_image: Image
var _terrain_wash_texture: ImageTexture
var _terrain_control_image: Image
var _terrain_control_texture: ImageTexture
var _grid_data: Dictionary = {} #stores vector2i -> terrain.base
#visual state trackers
var _active_decorations: Dictionary[Vector2i, Sprite2D] = {} #stores vector2i -> sprite2d
var _active_previews: Dictionary[Vector2i, Sprite2D] = {} #for preview sprites only
var _active_brush_strokes: Dictionary[Vector2i, Sprite2D]
#bounds management
#we track the top-left coordinate of the current image grid
var _min_coord: Vector2i = Vector2i.ZERO
var _size_cells: Vector2i = Vector2i(1, 1)

func start() -> void:
	if is_main_terrain_renderer:
		_setup_configuration()
	_setup_visuals()

	if show_debug_texture:
		_create_debug_view()

func _create_debug_view() -> void:
	var dr = TextureRect.new()
	dr.texture = _brush_viewport.get_texture()
	dr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	dr.scale = Vector2(5, 5)
	dr.position = Vector2(20, 20)
	var c = CanvasLayer.new()
	c.add_child(dr)
	add_child(c)

func _setup_configuration() -> void:
	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return
	RenderingServer.set_default_clear_color(profile.clear_color)
	color_rect.color = profile.ui_canvas_color
	_configure_paper_layers(profile)

func _configure_paper_layers(profile: EnvironmentProfile) -> void: ##separates broad paper folds from fine grain so each environment can tune them independently
	if is_instance_valid(paper_rect):
		var crumple_modulate: Color = paper_rect.modulate
		crumple_modulate.a = profile.paper_crumple_strength
		paper_rect.modulate = crumple_modulate

	if not is_instance_valid(paper_grain_rect):
		return
	var grain_material: ShaderMaterial = paper_grain_rect.material as ShaderMaterial
	if grain_material == null:
		return

	grain_material = grain_material.duplicate() as ShaderMaterial
	paper_grain_rect.material = grain_material
	grain_material.set_shader_parameter(&"grain_strength", profile.paper_grain_strength)
	grain_material.set_shader_parameter(&"grain_scale", profile.paper_grain_scale)
	grain_material.set_shader_parameter(&"grain_color", profile.paper_grain_color)
	grain_material.set_shader_parameter(&"brush_strength", profile.paper_brush_strength)

func _setup_visuals() -> void:
	if not _validate_authored_surfaces():
		return

	#initialize with a small empty grid
	_grid_image = Image.create(1, 1, false, Image.FORMAT_L8)
	_grid_texture = ImageTexture.create_from_image(_grid_image)
	_terrain_color_image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_terrain_color_image.fill(Color.TRANSPARENT)
	_terrain_color_texture = ImageTexture.create_from_image(_terrain_color_image)
	_terrain_wash_image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_terrain_wash_image.fill(Color.TRANSPARENT)
	_terrain_wash_texture = ImageTexture.create_from_image(_terrain_wash_image)
	_terrain_control_image = Image.create(1, 1, false, Image.FORMAT_L8)
	_terrain_control_image.fill(Color.BLACK)
	_terrain_control_texture = ImageTexture.create_from_image(_terrain_control_image)
	_brush_viewport = SubViewport.new()
	_brush_viewport.name = "BrushMaskViewport"
	_brush_viewport.disable_3d = true
	_brush_viewport.transparent_bg = true
	_brush_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_brush_viewport)

	var stain_material: ShaderMaterial = background_stain_rect.material.duplicate() as ShaderMaterial
	background_stain_rect.material = stain_material
	stain_material.set_shader_parameter(&"mask_texture", _brush_viewport.get_texture())

	var mat: ShaderMaterial = terrain_rect.material.duplicate() as ShaderMaterial
	terrain_rect.material = mat

	mat.set_shader_parameter("grid_data_texture", _grid_texture)
	mat.set_shader_parameter("terrain_color_texture", _terrain_color_texture)
	mat.set_shader_parameter("terrain_wash_texture", _terrain_wash_texture)
	mat.set_shader_parameter("terrain_control_texture", _terrain_control_texture)
	mat.set_shader_parameter("distance_field_step", 1.0 / maxf(max_gradient_depth, 0.001))
	if is_main_terrain_renderer:
		_bind_terrain_paper_grain_texture(mat)
	if apply_environment_material_overrides:
		_apply_environment_shader_configuration(mat)

	#pass the viewport's texture to the shader
	#note: viewport textures are dynamic and update with viewport contents
	mat.set_shader_parameter("brush_mask_texture", _brush_viewport.get_texture())

	_update_rect_transform()

func _validate_authored_surfaces() -> bool: ##requires inspector-authored draw surfaces so their materials and ordering remain directly editable
	if not is_instance_valid(terrain_rect):
		push_error("TerrainRenderer requires an authored terrain_rect ColorRect")
		return false
	if not terrain_rect.material is ShaderMaterial:
		push_error("TerrainRenderer terrain_rect requires a ShaderMaterial")
		return false
	if not is_instance_valid(background_stain_rect):
		push_error("TerrainRenderer requires an authored background_stain_rect ColorRect")
		return false
	if not background_stain_rect.material is ShaderMaterial:
		push_error("TerrainRenderer background_stain_rect requires a ShaderMaterial")
		return false
	if not is_instance_valid(decoration_container):
		push_error("TerrainRenderer requires an authored decoration_container Node2D")
		return false
	return true

func _apply_environment_shader_configuration(material: ShaderMaterial) -> void: ##applies environment-authored paint controls only to the main watercolor terrain surface
	if not is_main_terrain_renderer:
		return

	var profile: EnvironmentProfile = Run.get_environment_profile()
	if profile == null:
		return

	material.set_shader_parameter(&"cut_threshold", profile.terrain_cut_threshold)
	material.set_shader_parameter(&"edge_softness", profile.terrain_edge_softness)
	material.set_shader_parameter(&"center_falloff", profile.terrain_center_falloff)
	material.set_shader_parameter(&"brush_strength", profile.terrain_brush_strength)
	material.set_shader_parameter(&"min_paint_coverage", profile.terrain_min_paint_coverage)
	material.set_shader_parameter(&"terrain_color_strength", profile.terrain_color_strength)
	material.set_shader_parameter(&"terrain_transition_softness", profile.terrain_transition_softness)
	material.set_shader_parameter(&"terrain_warp_strength", profile.terrain_warp_strength)
	material.set_shader_parameter(&"paper_grain_strength", profile.paper_grain_strength)
	material.set_shader_parameter(&"paper_grain_scale", profile.paper_grain_scale)
	material.set_shader_parameter(&"posterization_strength", profile.terrain_posterization_strength)
	material.set_shader_parameter(&"posterization_levels", profile.terrain_posterization_levels)
	material.set_shader_parameter(&"coastline_color", profile.terrain_coastline_color)
	material.set_shader_parameter(&"coastline_strength", profile.terrain_coastline_strength)
	material.set_shader_parameter(&"coastline_width", profile.terrain_coastline_width)
	material.set_shader_parameter(&"waterline_strength", profile.terrain_waterline_strength)
	material.set_shader_parameter(&"waterline_width", profile.terrain_waterline_width)
	var waterline_level: float = profile.terrain_waterline_level
	if waterline_level < 0.0:
		var open_water_base: Terrain.Base = profile.get_open_water_base()
		var water_base_stat: TerrainBaseStat = Terrain.get_base_stat(open_water_base)
		waterline_level = water_base_stat.dominance_strength * water_base_stat.color.a * 0.5
	material.set_shader_parameter(&"waterline_level", waterline_level)

func _bind_terrain_paper_grain_texture(material: ShaderMaterial) -> void: ##binds the fine-grain layer's seamless noise while preserving inspector-authored strength and world-space addressing
	if not is_instance_valid(paper_grain_rect):
		push_warning("TerrainRenderer requires paper_grain_rect to texture watercolor pigment")
		return

	var grain_material: ShaderMaterial = paper_grain_rect.material as ShaderMaterial
	if grain_material == null:
		push_warning("TerrainRenderer paper_grain_rect requires a ShaderMaterial")
		return
	var grain_texture: Texture2D = grain_material.get_shader_parameter(&"grain_texture") as Texture2D
	if grain_texture == null:
		push_warning("TerrainRenderer paper grain material requires grain_texture")
		return

	material.set_shader_parameter(&"paper_grain_texture", grain_texture)

#accepts a list of tiles to add/remove to minimize resize operations
#changes: dictionary of { vector2i cell: terrain.base terrain }, or false to remove
func apply_terrain_changes(changes: Dictionary) -> void:
	if changes.is_empty():
		return
	var new_min := _min_coord
	var new_max := _min_coord + _size_cells - Vector2i.ONE

	#1. update logic and calculate new bounds
	for cell: Vector2i in changes:
		var change = changes[cell]
		var is_land: bool = not (change is bool and change == false)

		if is_land:
			_grid_data[cell] = _terrain_type_from_change(change)
			#expand bounds if necessary
			if _grid_data.size() == 1: #first tile
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
			#if a tile is removed, its decoration must also go
			if _active_decorations.has(cell):
				_active_decorations[cell].queue_free()
				_active_decorations.erase(cell)
			#note: we don't shrink bounds automatically as it's expensive
			#and islands usually grow. shrinking is optional optimization.

	#add padding to bounds for the gradient to fade out
	var padding = int(max_gradient_depth) + 2
	new_min -= Vector2i(padding, padding)
	new_max += Vector2i(padding, padding)

	#check if we need to resize image
	var current_max = _min_coord + _size_cells
	if new_min.x < _min_coord.x or new_min.y < _min_coord.y or new_max.x >= current_max.x or new_max.y >= current_max.y:
		_resize_grid(new_min, new_max - new_min + Vector2i.ONE)

	#2. recalculate distance field
	_update_distance_field()
	_update_terrain_color_map()

	_brush_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

#updates the stamped sprites on top of the blob
func update_decoration(cell: Vector2i, type: Terrain.Base) -> void:
	#1. remove existing decoration at this cell
	if _active_decorations.has(cell):
		_active_decorations[cell].queue_free()
		_active_decorations.erase(cell)

	#2. check if this terrain type has a visual icon
	var icon: Texture2D = Terrain.get_icon(type)
	if icon == null:
		return

	#3. create the stamp
	var sprite := Sprite2D.new()
	sprite.texture = icon

	#calculate position: center of the cell + random offset
	var center_pos = (Vector2(cell) * cell_size) + (Vector2.ONE * cell_size * 0.5)
	sprite.position = center_pos
	#random rotation and scale for "hand-drawn" feel
	sprite.rotation_degrees = randf_range(-2, 2)
	var s = randf_range(0.9, 1.1)
	sprite.scale = Vector2(s, s) * 0.05

	#slight transparency to blend with the watercolor
	sprite.modulate.a = 1.0

	decoration_container.add_child(sprite)
	_active_decorations[cell] = sprite

#clears all current sprites (both terrain decorations and feature previews)
func clear_decorations() -> void:
	for cell: Vector2i in _active_decorations:
		if is_instance_valid(_active_decorations[cell]):
			_active_decorations[cell].free()
	for cell: Vector2i in _active_previews:
		if is_instance_valid(_active_previews[cell]):
			_active_previews[cell].free()

	_active_decorations.clear()
	_active_previews.clear()

#stamps a specific tower preview sprite at a cell
func set_preview_feature(cell: Vector2i, tower_type: int) -> void:
	#clean up any existing decoration at this cell
	if _active_previews.has(cell):
		if is_instance_valid(_active_previews[cell]):
			_active_previews[cell].queue_free()
		_active_previews.erase(cell)

	if tower_type == -1: #towers.type.void
		return

	#fetch the sprite from towers static api
	var icon: Texture2D = Towers.get_tower_preview(tower_type)
	if icon == null:
		return

	#create the visual stamp
	var sprite := Sprite2D.new()
	sprite.scale = Vector2.ONE * 0.06
	sprite.texture = icon

	#position: strictly centered on the tile (unlike organic terrain which jitters)
	var center_pos = (Vector2(cell) * cell_size) + (Towers.get_tower_size(tower_type) * cell_size * 0.5)
	sprite.position = center_pos

	#add to the existing decoration container so it sits on top of the terrain/sketch
	decoration_container.add_child(sprite)
	_active_previews[cell] = sprite

#completely clears and replaces the terrain with the new set of tiles
func reset_grid(new_land_tiles: Array[Vector2i], terrain_by_cell: Dictionary = {}) -> void:
	#1. reset data
	_grid_data.clear()
	#clear image (make it all water)
	_grid_image.fill(Color.BLACK)
	_terrain_color_image.fill(Color.TRANSPARENT)
	_terrain_wash_image.fill(Color.TRANSPARENT)
	_terrain_control_image.fill(Color.BLACK)

	#if input is empty, just update texture and return
	if new_land_tiles.is_empty():
		_grid_texture.set_image(_grid_image)
		_terrain_color_texture.set_image(_terrain_color_image)
		_terrain_wash_texture.set_image(_terrain_wash_image)
		_terrain_control_texture.set_image(_terrain_control_image)
		return

	#calculate new bounds
	var min_c := new_land_tiles[0]
	var max_c := new_land_tiles[0]

	for cell in new_land_tiles:
		_grid_data[cell] = terrain_by_cell.get(cell, Terrain.Base.EARTH)

		min_c.x = min(min_c.x, cell.x)
		min_c.y = min(min_c.y, cell.y)
		max_c.x = max(max_c.x, cell.x)
		max_c.y = max(max_c.y, cell.y)

	#3. resize logic (similar to apply_terrain_changes)
	var padding = int(max_gradient_depth) + 2
	min_c -= Vector2i(padding, padding)
	max_c += Vector2i(padding, padding)
	var new_size = max_c - min_c + Vector2i.ONE

	_resize_grid(min_c, new_size)

	#4. update visual (recalculate distance field for the new set)
	_update_distance_field()
	_update_terrain_color_map()

#helper to modify shader parameters dynamically
func set_color_param(param_name: String, value: Color) -> void:
	(terrain_rect.material as ShaderMaterial).set_shader_parameter(param_name, value)

#--- internal logic ---
func _spawn_brush_stroke(cell: Vector2i) -> void:
	if _active_brush_strokes.has(cell):
		return

	#if not (cell.x % 2 == 0 and cell.y % 2 == 0):
		#return

	var brush_tex: Texture2D = brush_textures.pick_random()
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = brush_tex

	#calculate position
	#important: viewport coordinates are local to the viewport (0,0 is top left)
	#the terrainrect also draws from 0,0 locally.
	#we need to map the global grid coordinates to this local space.
	var cell_center: Vector2 = (Vector2(cell) * cell_size) + (Vector2.ONE * cell_size * 0.5)

	#since the viewport moves with the grid logic (via _update_rect_transform logic below),
	#we can just set positions relative to the grid origin if we structure it right.
	#however, simplest way: the viewport covers the exact same rect as terrain_rect.
	#so coordinates should be relative to _min_coord.

	var local_pos: Vector2 = cell_center - Vector2(_min_coord * cell_size)

	#store the sprite to update its position later if we shift the grid
	sprite.position = local_pos
	#randomisation
	sprite.rotation = 0.2 + randf() * TAU * 0.1
	sprite.modulate = Color(1,1,1, randf_range(0.5, 1.0))
	var s: float = (randf_range(0.6, 1.0)) * 0.2
	sprite.scale = Vector2(s, s)

	_brush_viewport.add_child(sprite)
	_active_brush_strokes[cell] = sprite

func _resize_grid(new_origin: Vector2i, new_size: Vector2i) -> void:
	#safeguard against massive accidental sizes
	if new_size.x > 4096 or new_size.y > 4096:
		push_warning("terrain grid growing very large: ", new_size)

	#create new blank image
	var new_img = Image.create(new_size.x, new_size.y, false, Image.FORMAT_L8)
	var new_color_img = Image.create(new_size.x, new_size.y, false, Image.FORMAT_RGBA8)
	var new_wash_img = Image.create(new_size.x, new_size.y, false, Image.FORMAT_RGBA8)
	var new_control_img = Image.create(new_size.x, new_size.y, false, Image.FORMAT_L8)
	new_color_img.fill(Color.TRANSPARENT)
	new_wash_img.fill(Color.TRANSPARENT)
	new_control_img.fill(Color.BLACK)

	#update state
	_grid_image = new_img
	_terrain_color_image = new_color_img
	_terrain_wash_image = new_wash_img
	_terrain_control_image = new_control_img
	_min_coord = new_origin
	_size_cells = new_size
	#update visual rect
	_update_rect_transform()

func _update_rect_transform() -> void:
	#place the rect in the world
	terrain_rect.position = Vector2(_min_coord * cell_size)
	terrain_rect.size = Vector2(_size_cells * cell_size)

	var margin: float = terrain_rect.size.x + 5.0
	background_stain_rect.position = terrain_rect.position - Vector2.ONE * margin
	background_stain_rect.size = terrain_rect.size + Vector2.ONE * margin * 2

	#adjust brush viewport size
	if _brush_viewport.size != Vector2i(terrain_rect.size):
		_brush_viewport.size = Vector2i(terrain_rect.size)

	#when _min_coord changes, the "local" position of existing brushes shifts.
	#we need to re-align existing brushes.
	for cell: Vector2i in _active_brush_strokes:
		var sprite: Sprite2D = _active_brush_strokes[cell]
		var cell_center_world = (Vector2(cell) * cell_size) + (Vector2.ONE * cell_size * 0.5)
		var local_pos = cell_center_world - terrain_rect.position
		sprite.position = local_pos
	_brush_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	#pass world info to shader
	var mat = terrain_rect.material as ShaderMaterial
	mat.set_shader_parameter("region_pixel_offset", terrain_rect.position)
	mat.set_shader_parameter("region_pixel_size", terrain_rect.size)
	mat.set_shader_parameter("terrain_color_texture_size", Vector2(_size_cells))

func _update_distance_field() -> void:
	#standard bfs logic, but offset by _min_coord
	_grid_image.fill(Color.BLACK) #clear image


	#initialize bfs seeds (land tiles)
	#simpler approach: fill image with 0.
	#set all land pixels to -1 (unvisited).
	#find all land pixels next to water -> queue.

	#map global _grid_data to local image pixels
	for global_pos in _grid_data:
		var local_pos = global_pos - _min_coord
		if local_pos.x >= 0 and local_pos.y >= 0 and local_pos.x < _size_cells.x and local_pos.y < _size_cells.y:
			#temporary marker for land
			_grid_image.set_pixelv(local_pos, Color(1, 1, 1, 1))

	#build bfs for gradient
	#this is computationally heavy for huge maps.
	#for now, do full rebuild for correctness.

	var local_queue: Array[Vector2i] = []
	var visited := {}

	#find boundary: land cells adjacent to empty/water
	#since _grid_image is padded, we can iterate internal area
	for x in range(1, _size_cells.x - 1):
		for y in range(1, _size_cells.y - 1):
			if _grid_image.get_pixel(x, y).r > 0.5: #is land
				var is_coast: bool = false
				#check 4 neighbors for water (black)
				if _grid_image.get_pixel(x+1, y).r < 0.5: is_coast = true
				elif _grid_image.get_pixel(x-1, y).r < 0.5: is_coast = true
				elif _grid_image.get_pixel(x, y+1).r < 0.5: is_coast = true
				elif _grid_image.get_pixel(x, y-1).r < 0.5: is_coast = true

				if is_coast:
					local_queue.append(Vector2i(x, y))
					visited[Vector2i(x, y)] = 1.0 #distance 1

	#bfs
	var head: int = 0
	while head < local_queue.size():
		var curr = local_queue[head]
		head += 1
		var dist = visited[curr]

		var neighbors: Array[Vector2i] = [Vector2i(0,1), Vector2i(0,-1), Vector2i(1,0), Vector2i(-1,0)]
		for n in neighbors:
			var next = curr + n
			#if it is land and we haven't assigned a distance yet
			#check bounds
			if next.x >= 0 and next.y >= 0 and next.x < _size_cells.x and next.y < _size_cells.y:
				#check if it is land (we marked land as white earlier)
				#and not visited (visited dict check)
				if _grid_image.get_pixelv(next).r > 0.5 and not visited.has(next):
					visited[next] = dist + 1.0
					local_queue.append(next)

	#3. write final values to image
	#we need to clear the simple boolean mask we made in step 1 and replace with gradient
	_grid_image.fill(Color.BLACK)

	for local_pos in visited:
		var d = visited[local_pos]
		var norm = d / max_gradient_depth
		norm = clamp(norm, 0.0, 1.0)
		_grid_image.set_pixelv(local_pos, Color(norm, norm, norm))

	_grid_texture.set_image(_grid_image)

func _update_terrain_color_map() -> void:
	_terrain_color_image.fill(Color.TRANSPARENT)
	_terrain_wash_image.fill(Color.TRANSPARENT)
	_terrain_control_image.fill(Color.BLACK)
	for global_pos: Vector2i in _grid_data:
		var local_pos: Vector2i = global_pos - _min_coord
		if local_pos.x < 0 or local_pos.y < 0 or local_pos.x >= _size_cells.x or local_pos.y >= _size_cells.y:
			continue

		var terrain_type: Terrain.Base = _grid_data[global_pos]
		var terrain_color := Terrain.get_color(terrain_type)
		terrain_color.a = clamp(terrain_color.a, 0.0, 1.0)
		_terrain_color_image.set_pixelv(local_pos, terrain_color)
		var wash_color := Terrain.get_wash_color(terrain_type)
		wash_color.a = clamp(wash_color.a, 0.0, 1.0)
		_terrain_wash_image.set_pixelv(local_pos, wash_color)
		var dominance := Terrain.get_dominance_strength(terrain_type) * terrain_color.a
		_terrain_control_image.set_pixelv(local_pos, Color(dominance, dominance, dominance))

	_terrain_color_texture.set_image(_terrain_color_image)
	_terrain_wash_texture.set_image(_terrain_wash_image)
	_terrain_control_texture.set_image(_terrain_control_image)

func _terrain_type_from_change(change) -> Terrain.Base:
	if change is int:
		return change
	return Terrain.Base.EARTH
