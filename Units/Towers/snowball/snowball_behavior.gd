extends Behavior
class_name SnowballBehavior

const CARDINAL_DIRS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
#cached objects
var _query: PhysicsShapeQueryParameters2D

func _init():
	_query = PhysicsShapeQueryParameters2D.new()
	_query.collide_with_areas = true
	_query.collide_with_bodies = false

func update(delta: float) -> void:
	_cooldown += delta
	
	if not _is_attack_possible():
		return

	# find best direction
	# we scan all 4 directions and pick the one with the most enemies
	var range_val: float = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE) as float
	range_val += Island.CELL_SIZE * 0.5 #this is meant to be tile-based, so the half-tile gets us from the origin to the edges of our tile
	var best_dir: Vector2 = Vector2.ZERO
	var max_score: float = 0.0
	for dir: Vector2 in CARDINAL_DIRS:
		var score: float = _scan_lane(dir, range_val)
		if score > max_score:
			max_score = score
			best_dir = dir
	
	#fire if valid
	if best_dir != Vector2.ZERO:
		_fire_snowball(best_dir, range_val)

func _scan_lane(dir: Vector2, max_dist: float) -> float:
	var my_pos := unit.global_position

	var space_state = unit.get_world_2d().direct_space_state
	var shape = RectangleShape2D.new()
	shape.size = Vector2(max_dist, Island.CELL_SIZE * 0.8) #slightly smaller to be purely inclusive
	
	_query.shape = shape
	_query.collision_mask = Hitbox.get_mask(not unit.hostile)
	
	# position the rect: it extends from center, so we need to offset it
	var center_point: Vector2 = my_pos + (dir * (max_dist / 2))
	var angle: float = dir.angle()
	_query.transform = Transform2D(angle, center_point)

	var results = space_state.intersect_shape(_query)
	
	# basic scoring: 1 point per enemy
	return float(results.size())

func _fire_snowball(dir: Vector2, range_val: float) -> void:
	#we need custom logic, so we cant use attack_component.attack
	#prepare Delivery Data
	var delivery_data := attack_component.generate_delivery_data()
	#projectile will despawn after reaching end of range
	delivery_data.projectile_lifetime = range_val / delivery_data.projectile_speed
	delivery_data.initial_velocity = dir * delivery_data.projectile_speed
	delivery_data.use_initial_velocity_override = true 
	
	var hit_data := attack_component.generate_hit_data(delivery_data)
	hit_data.target_affiliation = not unit.hostile
	hit_data.target = null # untargeted

	#we have no predestined intercept nor target
	CombatManager.resolve_hit(hit_data, delivery_data)
	#refresh cooldown for attackcomponent (since we're bypassing attack())
	attack_component.current_cooldown = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN)
	
	if is_instance_valid(animation_player):
		animation_player.play("attack")
