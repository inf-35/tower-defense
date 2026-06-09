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
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled:
		return

	var scan: Tower.ForwardScanResult = tower.scan_forward(49)
	var found_tower: Tower = scan.hit_tower

	#3. apply diff
	if found_tower != _currently_buffed_tower:
		_revoke_buff()

		if is_instance_valid(found_tower):
			_grant_buff(found_tower, scan.distance_tiles)
			_currently_buffed_tower = found_tower

	elif is_instance_valid(_currently_buffed_tower):
		_grant_buff(_currently_buffed_tower, scan.distance_tiles)

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
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower): return

	var scan: Tower.ForwardScanResult = tower.scan_forward(20)
	var target_tower: Tower = scan.hit_tower

	#3. draw
	var start_pos: Vector2 = Island.cell_to_position(tower.tower_position)

	if is_instance_valid(target_tower):
		#hit a tower
		var end_pos: Vector2 = Island.cell_to_position(scan.impact_cell)
		canvas.draw_line(start_pos, end_pos, canvas.highlight_color, 2.0)
		canvas.draw_cell(scan.impact_cell, canvas.highlight_color)
	else:
		#missed / hit nothing. draw a faded line up to the last checked cell.
		var end_pos: Vector2 = Island.cell_to_position(scan.last_valid_cell)

		#use a faded version of the highlight color
		var fade_color: Color = canvas.highlight_color
		fade_color.a *= 0.8

		canvas.draw_line(start_pos, end_pos, fade_color, 2.0)
