extends Behavior
class_name CommandPostBehavior

#--- configuration ---
@export var suppression_modifier: ModifierDataPrototype
@export var attacks_required: int = 1 ##number of adjacent attacks needed to trigger target

#--- state ---
var _target_tower: Tower = null
var _target_suppression_modifier: Modifier
var _my_neighbors: Dictionary[Tower, bool] = {}
var _attack_counter: int = 0

func start() -> void:
	if not suppression_modifier:
		push_warning("CommandPost: Missing suppression_modifier!")

	var tower = unit as Tower

	#1. listen to our own neighbors changing
	tower.adjacency_updated.connect(_on_my_adjacency_updated)
	_on_my_adjacency_updated(tower.get_adjacent_towers())

	Run.references.island.island_changed.connect(_recalculate_target)
	_recalculate_target()

func detach() -> void:
	_release_target()

#--- neighbor monitoring (the triggers) ---

func _on_my_adjacency_updated(adj_map: Dictionary) -> void:
	var current_neighbors: Dictionary[Tower, bool] = {}

	for n: Tower in adj_map.values():
		if is_instance_valid(n) and n != unit and n != _target_tower:
			current_neighbors[n] = true
			if not _my_neighbors.has(n):
				n.on_event.connect(_on_neighbor_event.bind(n))

	var to_remove = []
	for old_n in _my_neighbors:
		if not current_neighbors.has(old_n):
			if is_instance_valid(old_n) and old_n.on_event.is_connected(_on_neighbor_event):
				old_n.on_event.disconnect(_on_neighbor_event)
			to_remove.append(old_n)

	for n in to_remove:
		_my_neighbors.erase(n)

	_my_neighbors = current_neighbors

func _on_neighbor_event(event: GameEvent, _source: Tower) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT: return

	_attack_counter += 1
	if _attack_counter >= attacks_required:
		_attack_counter = 0
		_command_target_to_fire()

func _recalculate_target() -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled: return

	var island = Run.references.island
	if not is_instance_valid(island): return

	var forward_dir: Vector2i = Vector2i.ZERO
	match tower.facing:
		Tower.Facing.UP: forward_dir = Vector2i(0, -1)
		Tower.Facing.RIGHT: forward_dir = Vector2i(1, 0)
		Tower.Facing.DOWN: forward_dir = Vector2i(0, 1)
		Tower.Facing.LEFT: forward_dir = Vector2i(-1, 0)

	var current_cell = tower.tower_position + forward_dir
	var distance_tiles: int = 1
	var found_tower: Tower = null

	while distance_tiles < 50:
		if not island.terrain_base_grid.has(current_cell): break
		var check_tower = island.get_tower_on_tile(current_cell)
		if is_instance_valid(check_tower):
			if check_tower != tower:
				found_tower = check_tower
			break
		current_cell += forward_dir
		distance_tiles += 1

	if found_tower != _target_tower:
		_release_target()
		if is_instance_valid(found_tower):
			_bind_target(found_tower)

func _bind_target(target: Tower) -> void:
	_target_tower = target
	if is_instance_valid(_target_tower.attack_component):
		_target_tower.attack_component.current_cooldown = 10000.0
	_attack_counter = 0
	_target_suppression_modifier = suppression_modifier.generate_modifier()
	target.modifiers_component.add_modifier(_target_suppression_modifier)

func _release_target() -> void:
	print(_target_tower)
	if is_instance_valid(_target_tower):
		_target_tower.modifiers_component.remove_modifier(_target_suppression_modifier)
	_target_tower = null

#--- firing logic ---

func _command_target_to_fire() -> void:
	if not is_instance_valid(_target_tower) or not is_instance_valid(_target_tower.attack_component): return
	_target_tower.attack_component.current_cooldown = -1.0

	if is_instance_valid(animation_player):
		_play_animation(&"cast")

func _exit_tree() -> void:
	_release_target()
	for n in _my_neighbors:
		if is_instance_valid(n) and n.on_event.is_connected(_on_neighbor_event):
			n.on_event.disconnect(_on_neighbor_event)
	_my_neighbors.clear()

#--- visualizer ---

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower): return

	#1. highlight my neighbors (the triggers)
	var neighbors = tower.get_adjacent_cells()
	for n in neighbors:
		var fade_color = canvas.highlight_color
		fade_color.a *= 0.5
		canvas.draw_cell(n, fade_color)

	#2. draw line to target
	var island = Run.references.island
	if not is_instance_valid(island): return

	var target: Tower = null
	var impact_cell: Vector2i

	var forward_dir: Vector2i = Vector2i.ZERO
	#... (facing direction matching logic) ...
	match tower.facing:
		Tower.Facing.UP: forward_dir = Vector2i(0, -1)
		Tower.Facing.RIGHT: forward_dir = Vector2i(1, 0)
		Tower.Facing.DOWN: forward_dir = Vector2i(0, 1)
		Tower.Facing.LEFT: forward_dir = Vector2i(-1, 0)

	var current_cell = tower.tower_position + forward_dir
	var distance_tiles: int = 1

	while distance_tiles <= 20:
		if not island.terrain_base_grid.has(current_cell): break
		var check_tower = island.get_tower_on_tile(current_cell)
		if is_instance_valid(check_tower) and check_tower != tower:
			target = check_tower
			impact_cell = current_cell
			break
		current_cell += forward_dir
		distance_tiles += 1

	var start_pos = Island.cell_to_position(tower.tower_position)
	if is_instance_valid(target):
		var end_pos = Island.cell_to_position(impact_cell)
		canvas.draw_line(start_pos, end_pos, canvas.highlight_color, 2.0)
		canvas.draw_cell(impact_cell, canvas.highlight_color)
	else:
		var last_valid_cell = current_cell - forward_dir
		var end_pos = Island.cell_to_position(last_valid_cell)
		var fade_color = canvas.highlight_color
		fade_color.a *= 0.3
		canvas.draw_line(start_pos, end_pos, fade_color, 2.0)
