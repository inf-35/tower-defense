extends Behavior
class_name PrismBehavior

const PRISM_LASER_SCENE: PackedScene = preload("res://Units/Towers/prism/prism_laser.tscn")

#lasers that this tower instantiated and manages (right & down only)
var _owned_lasers: Dictionary[Tower, Node2D] = {}

#all valid connections (up, down, left, right) - useful for calculating network size
var _all_connected_prisms: Array[Tower] = []

func start() -> void:
	Run.references.island.island_changed.connect(_recalculate_links)
	_recalculate_links()

func update(_delta: float) -> void:
	#tick damage for the lasers we own
	if _is_attack_possible(false):
		for partner in _owned_lasers:
			var laser = _owned_lasers[partner]
			if is_instance_valid(laser) and laser.has_method("damage_tick"):
				laser.damage_tick()
		attack_component.refresh_cooldown()

func _recalculate_links() -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive: return

	var new_owned: Array[Tower] = []
	_all_connected_prisms.clear()

	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for d in dirs:
		var partner = _scan_direction(d)
		if is_instance_valid(partner):
			_all_connected_prisms.append(partner)

			#directional ownership: we only spawn the physical laser if it's right or down.
			#the other tower will handle left and up.
			if d == Vector2i.RIGHT or d == Vector2i.DOWN:
				new_owned.append(partner)

	#1. clean up broken links
	var to_remove: Array[Tower] = []
	for old_partner in _owned_lasers:
		if not new_owned.has(old_partner):
			to_remove.append(old_partner)

	for p in to_remove:
		_remove_prism_laser(p)

	#2. create new links
	for p in new_owned:
		if not _owned_lasers.has(p):
			_create_prism_laser(p)

func _scan_direction(dir: Vector2i) -> Tower:
	var island = Run.references.island
	var current_cell = (unit as Tower).tower_position + dir

	#scan until edge of map or hit a tower
	while island.terrain_base_grid.has(current_cell):
		var check_tower: Tower = island.get_tower_on_tile(current_cell) as Tower

		if is_instance_valid(check_tower):
			#if it's a prism, return it. if it's anything else (wall), block line of sight.
			if check_tower.type == (unit as Tower).type and (not check_tower.disabled):
				return check_tower
			else:
				return null

		current_cell += dir
	return null

#--- laser instantiation ---

func _create_prism_laser(partner: Tower) -> void:
	var prism_a: Tower = unit
	var laser = PRISM_LASER_SCENE.instantiate()

	laser.prism_a = prism_a
	laser.prism_b = partner
	_owned_lasers[partner] = laser

	Run.references.island.add_child.call_deferred(laser)

	#math
	var pos_a_world: Vector2 = Island.cell_to_position(prism_a.tower_position)
	var pos_b_world: Vector2 = Island.cell_to_position(partner.tower_position)
	var vector: Vector2 = pos_b_world - pos_a_world

	laser.global_position = pos_a_world + vector / 2.0
	laser.rotation = vector.angle()

	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(vector.length(), 3) #width = 8

	#assuming your laser scene has a variable for this
	laser.collision_shape.shape = shape

func _remove_prism_laser(partner: Tower) -> void:
	if _owned_lasers.has(partner):
		if is_instance_valid(_owned_lasers[partner]):
			_owned_lasers[partner].queue_free()
		_owned_lasers.erase(partner)

func _exit_tree() -> void:
	#cleanup owned lasers on destruction
	for p in _owned_lasers:
		_remove_prism_laser(p)

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower): return

	var island = Run.references.island
	if not is_instance_valid(island): return

	var start_pos = Island.cell_to_position(tower.tower_position)
	var dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for d in dirs:
		var current_cell = tower.tower_position + d
		var distance_tiles: int = 1
		var max_scan_distance = 50 #safeguard

		var hit_tower: Tower = null
		var impact_cell: Vector2i = tower.tower_position

		#cast ray
		while distance_tiles <= max_scan_distance:
			if not island.terrain_base_grid.has(current_cell):
				break #hit edge of the map

			var check_tower = island.get_tower_on_tile(current_cell)
			if is_instance_valid(check_tower) and check_tower != tower:
				hit_tower = check_tower
				impact_cell = current_cell
				break

			impact_cell = current_cell
			current_cell += d
			distance_tiles += 1

		var end_pos = Island.cell_to_position(impact_cell)

		#evaluate what we hit
		if is_instance_valid(hit_tower) and hit_tower.type == tower.type:
			#successful link to another prism
			canvas.draw_line(start_pos, end_pos, canvas.highlight_color, 2.0)
			canvas.draw_cell(impact_cell, canvas.highlight_color)
		else:
			#missed, or hit a blocking tower that isn't a prism
			var fade_color = canvas.highlight_color
			fade_color.a *= 0.3
			canvas.draw_line(start_pos, end_pos, fade_color, 2.0)

			#optional: if it hit a wall/non-prism, you could highlight the blockage in red
			if is_instance_valid(hit_tower):
				canvas.draw_cell(impact_cell, Color(1.0, 0.2, 0.2, 0.4))
