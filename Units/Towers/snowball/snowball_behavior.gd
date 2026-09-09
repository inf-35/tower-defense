extends Behavior
class_name SnowballBehavior

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]
const LANE_INFLUENCE_PREFIX: String = "snowball_lane_"
const BLOCKER_INFLUENCE_PREFIX: String = "snowball_blocker_"

#cached objects
var _query: PhysicsShapeQueryParameters2D

func _init() -> void: ##prepares a reusable broad-phase query object for cardinal lane scans
	_query = PhysicsShapeQueryParameters2D.new()
	_query.collide_with_areas = true
	_query.collide_with_bodies = false

func update(delta: float) -> void: ##fires one four-way snowball volley when at least one cardinal lane has enemies
	_cooldown += delta

	if not _is_attack_possible(false):
		return

	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return

	var range_val: float = _get_lane_range()
	var directions: Array[Vector2i] = _get_ordered_cardinal_directions(tower)
	if not _has_lane_targets(directions, range_val):
		return

	_fire_snowball_volley(directions, range_val)

func _get_lane_range() -> float: ##returns authored range plus half a tile so lane projectiles reach the far edge of the last covered cell
	var range_val: float = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE) as float
	return range_val + Island.CELL_SIZE * 0.5

func _get_ordered_cardinal_directions(tower: Tower) -> Array[Vector2i]: ##orders the four volley lanes with the tower's facing direction first for primary-hit semantics
	var ordered_directions: Array[Vector2i] = []
	var forward_direction: Vector2i = tower.get_forward_direction()
	if CARDINAL_DIRECTIONS.has(forward_direction):
		ordered_directions.append(forward_direction)

	for direction: Vector2i in CARDINAL_DIRECTIONS:
		if ordered_directions.has(direction):
			continue
		ordered_directions.append(direction)

	return ordered_directions

func _has_lane_targets(directions: Array[Vector2i], range_val: float) -> bool: ##checks whether any of the four lanes justifies spending the volley cooldown
	for direction: Vector2i in directions:
		if _scan_lane(Vector2(direction), range_val) > 0.0:
			return true
	return false

func _scan_lane(dir: Vector2, max_dist: float) -> float: ##estimates lane value by counting hittable enemies inside a narrow rectangular sweep
	var my_pos: Vector2 = unit.global_position

	var space_state: PhysicsDirectSpaceState2D = unit.get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(max_dist, Island.CELL_SIZE * 0.8) #slightly smaller to be purely inclusive

	_query.shape = shape
	_query.collision_mask = Hitbox.get_mask(not unit.hostile)

	#position the rect: it extends from center, so we need to offset it
	var center_point: Vector2 = my_pos + (dir * (max_dist / 2))
	var angle: float = dir.angle()
	_query.transform = Transform2D(angle, center_point)

	var results: Array[Dictionary] = space_state.intersect_shape(_query)

	#basic scoring: 1 point per enemy
	return float(results.size())

func _fire_snowball_volley(directions: Array[Vector2i], range_val: float) -> void: ##consumes one attack context, emits four same-frame directional payloads, and spends cooldown once
	var attack_context: AttackComponent.AttackLineageContext = attack_component.pull_attack_context()
	if not is_instance_valid(attack_context):
		return

	unit.play_action_squash_stretch()
	if is_instance_valid(animation_player):
		animation_player.play("attack")

	for direction_index: int in directions.size():
		var direction: Vector2 = Vector2(directions[direction_index])
		_fire_snowball(direction, range_val, attack_context, direction_index == 0)

	#refresh cooldown for attackcomponent (since we're bypassing attack())
	attack_component.current_cooldown = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN)

func _fire_snowball(dir: Vector2, range_val: float, attack_context: AttackComponent.AttackLineageContext, primary: bool) -> void: ##builds one untargeted directional projectile within the current four-way volley
	#we need custom logic, so we cant use attack_component.attack
	var delivery_data := attack_component.generate_delivery_data()
	#projectile will despawn after reaching end of range
	delivery_data.projectile_lifetime = range_val / delivery_data.projectile_speed
	delivery_data.initial_velocity = dir * delivery_data.projectile_speed
	delivery_data.use_initial_velocity_override = true

	var hit_data := attack_component.generate_hit_data(delivery_data)
	hit_data.target_affiliation = not unit.hostile
	hit_data.target = null #untargeted
	hit_data.attack_id = AttackComponent.get_next_attack_id()
	hit_data.primary = primary

	if not attack_component.apply_attack_context(hit_data, attack_context):
		return

	#we have no predestined intercept nor target
	unit.deal_hit(hit_data, delivery_data)

func draw_visuals(canvas: RangeIndicator) -> void: ##draws terrain eligibility and the circular range shared by all four firing lanes
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower): return
	_draw_allowed_terrain_visuals(canvas, tower)

	var range_val: float = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)
	_draw_circular_range_visual(canvas, tower, range_val)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes four visual-only attack lines without publishing them as tower-affecting relationships
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or not is_instance_valid(attack_component) or not is_instance_valid(attack_component.attack_data):
		return []
	var range_val: float = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)
	var range_tiles: int = floori(range_val / Island.CELL_SIZE)
	if range_tiles <= 0:
		return []

	var influences: Array[TowerInfluence] = []
	var directions: Array[Vector2i] = _get_ordered_cardinal_directions(tower)
	for direction_index: int in directions.size():
		var direction: Vector2i = directions[direction_index]
		var scan: Tower.ForwardScanResult = tower.scan_direction(direction, range_tiles)
		if scan.distance_tiles <= 0:
			continue
		var attack_distance: int = scan.distance_tiles - 1 if is_instance_valid(scan.hit_tower) else scan.distance_tiles
		var lane_cells: Array[Vector2i] = []
		for distance: int in range(1, attack_distance + 1):
			lane_cells.append(tower.tower_position + direction * distance)
		influences.append(TowerInfluence.for_line(
			StringName(LANE_INFLUENCE_PREFIX + str(direction_index)),
			TowerInfluence.Kind.ATTACK,
			lane_cells,
			Island.cell_to_position(tower.tower_position),
			Island.cell_to_position(scan.impact_cell),
			[],
			null,
			[],
			false,
			TowerInfluence.Scope.WORLD,
			TowerInfluence.VisualRole.ATTACK,
			0.5,
			1.0
		))
		if is_instance_valid(scan.hit_tower):
			influences.append(TowerInfluence.for_cells(
				StringName(BLOCKER_INFLUENCE_PREFIX + str(direction_index)),
				TowerInfluence.Kind.NEGATIVE,
				[scan.impact_cell],
				null,
				[],
				false,
				TowerInfluence.Scope.WORLD
			))
	return influences

func _draw_circular_range_visual(canvas: RangeIndicator, tower: Tower, range_val: float) -> void: ##restores the standard range ring so snowball range reads consistently with other towers
	if range_val <= 0.0:
		return
	canvas.preview_circle(tower.global_position, range_val, canvas.range_color, false, canvas.line_width)
