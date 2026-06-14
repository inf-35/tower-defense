extends Behavior
class_name WatchtowerBehavior

#--- configuration ---
@export var buff_per_tile: float = 0.5 ##e.g., 0.5 = +50% range per tile
@export var max_bonus_multiplier: float = 2.5 ##caps the additive range bonus at +250%
@export var beam_vfx: VFXInfo ##authored persistent beam settings used while this tower is actively linked to a forward target

#--- state ---
var _currently_buffed_tower: Tower = null
var _active_modifier: Modifier = null
var _beam_vfx: SwirlLineVFX = null

func start() -> void: ##binds the forward target and starts maintaining the persistent support beam for the live link
	Run.references.island.island_changed.connect(func(): _recalculate_target())
	set_process(true)
	_recalculate_target()

func detach() -> void: ##clears both the stat link and its beam when the tower is disabled or removed from play
	_revoke_buff()

func _process(_delta: float) -> void: ##keeps the live beam snapped to both tower centers while the link exists
	_refresh_beam()

func _recalculate_target() -> void: ##rescans the forward lane and keeps the modifier plus beam aligned to the current tower target
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled:
		_revoke_buff()
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

	_refresh_beam()

func _grant_buff(target: Tower, distance: int) -> void: ##applies one persistent range modifier and mutates it in place when only the magnitude changes
	if not is_instance_valid(target.modifiers_component):
		return

	var final_multiplier: float = 1.0 + minf(float(distance) * buff_per_tile, max_bonus_multiplier)

	if is_instance_valid(_active_modifier):
		if not is_equal_approx(_active_modifier.multiplicative, final_multiplier):
			_active_modifier.multiplicative = final_multiplier
			target.modifiers_component.change_modifier(_active_modifier)
	else:
		_active_modifier = Modifier.new(Attributes.id.RANGE, final_multiplier, 0.0, -1.0)
		target.modifiers_component.add_modifier(_active_modifier)

func _revoke_buff() -> void: ##removes the active stat link and tears down any beam still pointing at the old target
	if is_instance_valid(_currently_buffed_tower) and is_instance_valid(_active_modifier):
		if is_instance_valid(_currently_buffed_tower.modifiers_component):
			_currently_buffed_tower.modifiers_component.remove_modifier(_active_modifier)

	_active_modifier = null
	_currently_buffed_tower = null
	_clear_beam()

func _refresh_beam() -> void: ##owns the persistent beam lifecycle so the visual always mirrors the current support target
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or not is_instance_valid(_currently_buffed_tower) or tower.disabled or _currently_buffed_tower.disabled:
		_clear_beam()
		return

	var start_position: Vector2 = tower.global_position
	var end_position: Vector2 = _currently_buffed_tower.global_position
	if start_position.is_equal_approx(end_position):
		_clear_beam()
		return

	if not is_instance_valid(_beam_vfx):
		_beam_vfx = VFXManager.create_swirl_beam_info(beam_vfx, start_position, end_position)
		return

	_beam_vfx.set_segment(start_position, end_position)

func _clear_beam() -> void: ##frees the persistent beam defensively because the target can disappear before this behavior does
	if is_instance_valid(_beam_vfx):
		_beam_vfx.stop()
	_beam_vfx = null

func _exit_tree() -> void: ##cleans up the support link if the node is freed without going through the normal detach flow
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
