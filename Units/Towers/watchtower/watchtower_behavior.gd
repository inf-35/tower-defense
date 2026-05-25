extends Behavior
class_name WatchtowerBehavior

# --- Configuration ---
@export var buff_per_tile: float = 20 ## e.g., +20 range per tile
@export var base_buff: float = 20 ## e.g., base +20 range

# --- State ---
var _currently_buffed_tower: Tower = null
var _active_modifier: Modifier = null

func start() -> void:
	References.island.island_changed.connect(func(): _recalculate_target())
	_recalculate_target()
	
func detach():
	_revoke_buff()

func _recalculate_target() -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled:
		return
		
	var island = References.island
	if not is_instance_valid(island): return
	
	# 1. Determine Forward Vector
	var forward_dir := Vector2i.ZERO
	match tower.facing:
		Tower.Facing.UP: forward_dir = Vector2i(0, -1)
		Tower.Facing.RIGHT: forward_dir = Vector2i(1, 0)
		Tower.Facing.DOWN: forward_dir = Vector2i(0, 1)
		Tower.Facing.LEFT: forward_dir = Vector2i(-1, 0)
		
	# 2. Scan Forward Tile by Tile
	var current_cell = tower.tower_position + forward_dir
	var distance_tiles = 1
	var found_tower: Tower = null
	
	while distance_tiles < 50:
		if not island.terrain_base_grid.has(current_cell):
			break
			
		var check_tower = island.get_tower_on_tile(current_cell)
		if is_instance_valid(check_tower):
			# Don't buff other Watchtowers (optional design choice to prevent infinite loops)
			if check_tower != tower:
				found_tower = check_tower
			break
			
		current_cell += forward_dir
		distance_tiles += 1

	# 3. Apply Diff
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
		
	# Calculate Multiplier: Base + (Distance * BuffPerTile)
	# e.g. Distance 3 = 1.0 (Base) + 0.5 + (3 * 0.2) = 1.0 + 1.1 = 2.1x Range
	var final_bonus = base_buff + ((distance-1) * buff_per_tile)
	
	if is_instance_valid(_active_modifier):
		# We already have a modifier on this target, just update the math
		if not is_equal_approx(_active_modifier.additive, final_bonus):
			_active_modifier.additive = final_bonus
			target.modifiers_component.change_modifier(_active_modifier)
	else:
		# Create a fresh modifier and push it to the target
		_active_modifier = Modifier.new(Attributes.id.RANGE, 1.0, final_bonus, -1.0)
		target.modifiers_component.add_modifier(_active_modifier)

func _revoke_buff() -> void:
	if is_instance_valid(_currently_buffed_tower) and is_instance_valid(_active_modifier):
		if is_instance_valid(_currently_buffed_tower.modifiers_component):
			_currently_buffed_tower.modifiers_component.remove_modifier(_active_modifier)
			
	_active_modifier = null
	_currently_buffed_tower = null

func _exit_tree() -> void:
	# Clean up the buff when this Watchtower is sold/destroyed
	_revoke_buff()

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower = unit as Tower
	if not is_instance_valid(tower): return
	
	var island = References.island
	if not is_instance_valid(island): return
	
	var target_tower: Tower = null
	var impact_cell: Vector2i
	
	# 1. Determine Forward Vector
	var forward_dir := Vector2i.ZERO
	match tower.facing:
		Tower.Facing.UP: forward_dir = Vector2i(0, -1)
		Tower.Facing.RIGHT: forward_dir = Vector2i(1, 0)
		Tower.Facing.DOWN: forward_dir = Vector2i(0, 1)
		Tower.Facing.LEFT: forward_dir = Vector2i(-1, 0)

	# 2. Scanning Logic (We do this for both Preview and Live to get the exact impact cell)
	var current_cell = tower.tower_position + forward_dir
	var distance_tiles = 1
	var max_scan_distance = 20 # Fallback distance if nothing is hit
	
	while distance_tiles <= max_scan_distance:
		# If we hit the edge of the charted map, we can stop the ray
		if not island.terrain_base_grid.has(current_cell):
			break
			
		var check_tower = island.get_tower_on_tile(current_cell)
		if is_instance_valid(check_tower) and check_tower != tower:
			target_tower = check_tower
			impact_cell = current_cell # The exact tile we hit, not the tower origin
			break
			
		current_cell += forward_dir
		distance_tiles += 1

	# 3. Draw
	var start_pos = Island.cell_to_position(tower.tower_position)
	
	if is_instance_valid(target_tower):
		# Hit a tower
		var end_pos = Island.cell_to_position(impact_cell)
		canvas.draw_line(start_pos, end_pos, canvas.highlight_color, 2.0)
		canvas.draw_cell(impact_cell, canvas.highlight_color)
	else:
		# Missed / Hit nothing. Draw a faded line up to the last checked cell.
		# Back up one step so we don't draw into the void/edge
		var last_valid_cell = current_cell - forward_dir
		var end_pos = Island.cell_to_position(last_valid_cell)
		
		# Use a faded version of the highlight color
		var fade_color = canvas.highlight_color
		fade_color.a *= 0.8
		
		canvas.draw_line(start_pos, end_pos, fade_color, 2.0)
