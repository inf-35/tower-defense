extends Behavior
class_name PrismBehavior

const PRISM_LASER_SCENE: PackedScene = preload("res://Units/Towers/prism/prism_laser.tscn")

var _owned_lasers: Dictionary[Tower, Node2D] = {}
var _all_connected_prisms: Array[Tower] = []
var _is_attached: bool = false

func start() -> void:
	attach()

func attach() -> void:
	if _is_attached:
		return

	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	_is_attached = true
	if not island.island_changed.is_connected(_recalculate_links):
		island.island_changed.connect(_recalculate_links)
	island.island_changed.emit()

func detach() -> void:
	var island: Island = null
	if is_instance_valid(Run.references.island):
		island = Run.references.island
		if island.island_changed.is_connected(_recalculate_links):
			island.island_changed.disconnect(_recalculate_links)

	_is_attached = false
	_all_connected_prisms.clear()
	_clear_prism_lasers()
	if is_instance_valid(island):
		island.island_changed.emit()

func update(_delta: float) -> void:
	if not _is_ready_to_pulse():
		return

	var targets: Array[Unit] = _collect_beam_targets()
	if targets.is_empty():
		return
	
	var attack_context: AttackComponent.AttackLineageContext = attack_component.pull_attack_context()
	if not is_instance_valid(attack_context):
		return

	attack_component.current_cooldown = attack_component.cooldown * 2.0
	for target: Unit in targets:
		attack_component.attack_with_context(target, attack_context, Vector2.ZERO, false)

func _is_ready_to_pulse() -> bool: ##keeps prism firing on its own half-cooldown cadence rather than delegating cadence to the beam nodes
	return is_instance_valid(attack_component) and not unit.disabled and attack_component.current_cooldown <= 0.0

func _collect_beam_targets() -> Array[Unit]: ##collects targets from every beam this prism participates in so the prism remains the sole attack source
	var targets: Array[Unit] = []
	for partner: Tower in _all_connected_prisms:
		if not _is_valid_active_prism(partner):
			continue

		var laser: PrismLaser = _get_laser_for_partner(partner)
		if not is_instance_valid(laser):
			continue

		targets.append_array(laser.get_targets())
	return targets

func _get_laser_for_partner(partner: Tower) -> PrismLaser: ##resolves the shared beam node for a prism link regardless of which endpoint owns the visual node
	if _owned_lasers.has(partner):
		return _owned_lasers[partner] as PrismLaser

	var partner_behavior: PrismBehavior = partner.behavior as PrismBehavior
	if not is_instance_valid(partner_behavior):
		return null
	if not partner_behavior._owned_lasers.has(unit):
		return null
	return partner_behavior._owned_lasers[unit as Tower] as PrismLaser

func _recalculate_links() -> void:
	if not _is_attached:
		return

	var tower: Tower = unit as Tower
	if not _is_valid_active_prism(tower):
		_clear_prism_lasers()
		return

	var new_owned: Array[Tower] = []
	_all_connected_prisms.clear()

	var dirs: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

	for d: Vector2i in dirs:
		var partner: Tower = _scan_direction(d)
		if is_instance_valid(partner):
			_all_connected_prisms.append(partner)

			if d == Vector2i.RIGHT or d == Vector2i.DOWN:
				new_owned.append(partner)

	var to_remove: Array[Tower] = []
	var old_partners: Array[Tower] = []
	old_partners.assign(_owned_lasers.keys())
	for old_partner: Tower in old_partners:
		if not new_owned.has(old_partner):
			to_remove.append(old_partner)

	for partner: Tower in to_remove:
		_remove_prism_laser(partner)

	for partner: Tower in new_owned:
		if not _owned_lasers.has(partner):
			_create_prism_laser(partner)

func _scan_direction(dir: Vector2i) -> Tower:
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return null

	var tower: Tower = unit as Tower
	if not _is_valid_active_prism(tower):
		return null

	var current_cell: Vector2i = tower.tower_position + dir

	while island.terrain_base_grid.has(current_cell):
		var check_tower: Tower = island.get_tower_on_tile(current_cell) as Tower

		if is_instance_valid(check_tower):
			if _is_valid_active_prism(check_tower) and check_tower.type == tower.type:
				return check_tower

			return null

		current_cell += dir
	return null

func _create_prism_laser(partner: Tower) -> void: ##reserves a prism link immediately, then defers node insertion until the tree is out of any teardown/setup critical section
	var prism_a: Tower = unit as Tower
	if not _is_valid_active_prism(prism_a) or not _is_valid_active_prism(partner):
		return

	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	var laser: PrismLaser = PRISM_LASER_SCENE.instantiate() as PrismLaser
	if not is_instance_valid(laser):
		return

	laser.prism_a = prism_a
	laser.prism_b = partner
	_owned_lasers[partner] = laser
	call_deferred("_finalize_prism_laser_creation", partner, laser)

func _finalize_prism_laser_creation(partner: Tower, laser: PrismLaser) -> void: ##finishes the deferred prism laser spawn only if the reserved link still exists and both endpoint prisms remain valid
	if not _owned_lasers.has(partner):
		if is_instance_valid(laser):
			laser.queue_free()
		return

	if _owned_lasers[partner] != laser:
		if is_instance_valid(laser):
			laser.queue_free()
		return

	var prism_a: Tower = unit as Tower
	if not _is_valid_active_prism(prism_a) or not _is_valid_active_prism(partner):
		_remove_prism_laser(partner)
		return

	var island: Island = Run.references.island
	if not is_instance_valid(island):
		_remove_prism_laser(partner)
		return

	var pos_a_world: Vector2 = Island.cell_to_position(prism_a.tower_position)
	var pos_b_world: Vector2 = Island.cell_to_position(partner.tower_position)
	var vector: Vector2 = pos_b_world - pos_a_world

	island.add_child(laser)
	laser.global_position = pos_a_world + vector / 2.0
	laser.rotation = vector.angle()

	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(vector.length(), 3)

	laser.collision_shape.shape = shape

func _remove_prism_laser(partner: Tower) -> void:
	if not _owned_lasers.has(partner):
		return

	var laser: Node2D = _owned_lasers[partner]
	_owned_lasers.erase(partner)
	if is_instance_valid(laser):
		laser.queue_free()

func _clear_prism_lasers() -> void:
	var partners: Array[Tower] = []
	partners.assign(_owned_lasers.keys())
	for partner: Tower in partners:
		_remove_prism_laser(partner)

func _is_valid_active_prism(tower: Tower) -> bool:
	return is_instance_valid(tower) and not tower.is_queued_for_deletion() and not tower.abstractive and not tower.disabled

func _exit_tree() -> void:
	detach()

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
			canvas.preview_line(start_pos, end_pos, canvas.highlight_color, 2.0)
			canvas.draw_cell(impact_cell, canvas.highlight_color)
		else:
			#missed, or hit a blocking tower that isn't a prism
			var fade_color = canvas.highlight_color
			fade_color.a *= 0.3
			canvas.preview_line(start_pos, end_pos, fade_color, 2.0)

			#optional: if it hit a wall/non-prism, you could highlight the blockage in red
			if is_instance_valid(hit_tower):
				canvas.draw_cell(impact_cell, Color(1.0, 0.2, 0.2, 0.4))
