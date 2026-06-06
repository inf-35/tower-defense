extends Behavior
class_name WatchtowerBehavior

#--- configuration ---
@export var buff_per_tile: float = 20 ##e.g., +20 range per tile
@export var base_buff: float = 20 ##e.g., base +20 range

#--- state ---
var _currently_buffed_tower: Tower = null
var _active_modifier: Modifier = null

func start() -> void:
	Run.references.island.island_changed.connect(func(): _recalculate_target())
	_recalculate_target()

func detach() -> void:
	_revoke_buff()

func _recalculate_target() -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled:
		return

	var island = Run.references.island
	if not is_instance_valid(island): return

	#1. determine forward vector
	var forward_dir: Vector2i = Vector2i.ZERO
	match tower.facing:
		Tower.Facing.UP: forward_dir = Vector2i(0, -1)
		Tower.Facing.RIGHT: forward_dir = Vector2i(1, 0)
		Tower.Facing.DOWN: forward_dir = Vector2i(0, 1)
		Tower.Facing.LEFT: forward_dir = Vector2i(-1, 0)

	#2. scan forward tile by tile
	var current_cell = tower.tower_position + forward_dir
	var distance_tiles: int = 1
	var found_tower: Tower = null

	while distance_tiles < 50:
		if not island.terrain_base_grid.has(current_cell):
			break

		var check_tower = island.get_tower_on_tile(current_cell)
		if is_instance_valid(check_tower):
			#don't buff other watchtowers (optional design choice to prevent infinite loops)
			if check_tower != tower:
				found_tower = check_tower
			break

		current_cell += forward_dir
		distance_tiles += 1

	#3. apply diff
	if found_tower != _currently_buffed_tower:
		_revoke_buff()

		if is_instance_valid(found_tower):
			_grant_buff(found_tower, distance_tiles)
			_currently_buffed_tower = found_tower

	elif is_instance_valid(_currently_buffed_tower):
		_grant_buff(_currently_buffed_tower, distance_tiles)

func _grant_buff(target: Tower, distance: int) -> void:
	if not is_instance_valid(target.modifiers_component):
		return

	#calculate multiplier: base + (distance * buffpertile)
	#e.g. distance 3 = 1.0 (base) + 0.5 + (3 * 0.2) = 1.0 + 1.1 = 2.1x range
	var final_bonus = base_buff + ((distance-1) * buff_per_tile)

	if is_instance_valid(_active_modifier):
		#we already have a modifier on this target, just update the math
		if not is_equal_approx(_active_modifier.additive, final_bonus):
			_active_modifier.additive = final_bonus
			target.modifiers_component.change_modifier(_active_modifier)
	else:
		#create a fresh modifier and push it to the target
		_active_modifier = Modifier.new(Attributes.id.RANGE, 1.0, final_bonus, -1.0)
		target.modifiers_component.add_modifier(_active_modifier)

func _revoke_buff() -> void:
	if is_instance_valid(_currently_buffed_tower) and is_instance_valid(_active_modifier):
		if is_instance_valid(_currently_buffed_tower.modifiers_component):
			_currently_buffed_tower.modifiers_component.remove_modifier(_active_modifier)

	_active_modifier = null
	_currently_buffed_tower = null

func _exit_tree() -> void:
	#clean up the buff when this watchtower is sold/destroyed
	_revoke_buff()

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower): return

	var island = Run.references.island
	if not is_instance_valid(island): return

	var target_tower: Tower = null
	var impact_cell: Vector2i

	#1. determine forward vector
	var forward_dir: Vector2i = Vector2i.ZERO
	match tower.facing:
		Tower.Facing.UP: forward_dir = Vector2i(0, -1)
		Tower.Facing.RIGHT: forward_dir = Vector2i(1, 0)
		Tower.Facing.DOWN: forward_dir = Vector2i(0, 1)
		Tower.Facing.LEFT: forward_dir = Vector2i(-1, 0)

	#2. scanning logic (we do this for both preview and live to get the exact impact cell)
	var current_cell = tower.tower_position + forward_dir
	var distance_tiles: int = 1
	var max_scan_distance = 20 #fallback distance if nothing is hit

	while distance_tiles <= max_scan_distance:
		#if we hit the edge of the charted map, we can stop the ray
		if not island.terrain_base_grid.has(current_cell):
			break

		var check_tower = island.get_tower_on_tile(current_cell)
		if is_instance_valid(check_tower) and check_tower != tower:
			target_tower = check_tower
			impact_cell = current_cell #the exact tile we hit, not the tower origin
			break

		current_cell += forward_dir
		distance_tiles += 1

	#3. draw
	var start_pos = Island.cell_to_position(tower.tower_position)

	if is_instance_valid(target_tower):
		#hit a tower
		var end_pos = Island.cell_to_position(impact_cell)
		canvas.draw_line(start_pos, end_pos, canvas.highlight_color, 2.0)
		canvas.draw_cell(impact_cell, canvas.highlight_color)
	else:
		#missed / hit nothing. draw a faded line up to the last checked cell.
		#back up one step so we don't draw into the void/edge
		var last_valid_cell = current_cell - forward_dir
		var end_pos = Island.cell_to_position(last_valid_cell)

		#use a faded version of the highlight color
		var fade_color = canvas.highlight_color
		fade_color.a *= 0.8

		canvas.draw_line(start_pos, end_pos, fade_color, 2.0)
