extends Node #CombatManager

const _DEBUG: bool = false

class ProjectileAbstractResolver extends RefCounted: #fire and forget delegate for ProjectileAbstract (see resolve_hit)
	const ERROR_TOLERANCE : float = 30.0 #error tolerance for no AOE projectiles.
	const ERROR_TOLERANCE_SQUARED : float = ERROR_TOLERANCE ** 2 #length_squared optimisation
	
	static var circle_shape := CircleShape2D.new() #we share the same circleshape object across all checks
	static var timer_scene := SceneTree.new()
	
	var hit_data : HitData
	var delivery_data : DeliveryData
	var intercept_position : Vector2
	var source_position: Vector2
	var target_affiliation : bool 
	
	func _init(_hit_data: HitData, _delivery_data: DeliveryData):
		hit_data = _hit_data
		delivery_data = _delivery_data
		intercept_position = delivery_data.intercept_position
		target_affiliation = hit_data.target_affiliation
		if is_instance_valid(hit_data.target):
			target_affiliation = hit_data.target.hostile
		
		if delivery_data.use_source_position_override: #if we use a custom override source position
			source_position = delivery_data.source_position #use the source position+
		else: #otherwise default to source's muzzle / overall position
			source_position = hit_data.source.attack_component.muzzle.global_position\
				if is_instance_valid(hit_data.source.attack_component.muzzle) else hit_data.source.global_position
	
	func start():
		var source_to_target_normalized : Vector2 = (intercept_position - source_position).normalized()
		var starting_velocity: Vector2 = delivery_data.projectile_speed * source_to_target_normalized
		var delay: float = (intercept_position - source_position).length() / delivery_data.projectile_speed
		
		if delivery_data.use_initial_velocity_override: #we probably have no intercept position
			starting_velocity = delivery_data.initial_velocity
			delay = delivery_data.projectile_lifetime
		
		VFXManager.play_vfx(hit_data.vfx_on_spawn, source_position, starting_velocity, delay)
		Clock.await_game_time(delay).connect(func():
			_on_timeout()
		)
	
	func _on_timeout():
		VFXManager.play_vfx(hit_data.vfx_on_impact, intercept_position)
		Audio.play_sound(ID.Sounds.ENEMY_HIT_SOUND, intercept_position)
		var target : Unit = hit_data.target #NOTE: this might be null

		Targeting.add_damage(hit_data.target, -hit_data.expected_damage) #remove expected damage 
		if is_zero_approx(hit_data.radius): #this projectile has no aoe, so we just look for the primary target
			if not is_instance_valid(target):
				return
			if (target.position - intercept_position).length_squared() > ERROR_TOLERANCE_SQUARED:
				return #we missed by over error tolerance
				
			target.take_hit(hit_data)
			return
		#if we reach here, the projectile has some aoe
		var units: Array[Unit] = CombatManager.get_units_in_radius(hit_data.radius, intercept_position, target_affiliation)
		for unit_hit: Unit in units:
			var hit_copy = hit_data.duplicate()
			hit_copy.target = unit_hit
			unit_hit.take_hit(hit_copy)
			
class ProjectileSimulatedResolver extends RefCounted: #fire and forget delegate for ProjectileSimulated (see resolve_hit)
	const base_homing: float = 1.0 # sleight of hand to reduce misses
	
	var hit_data: HitData
	var delivery_data: DeliveryData
	var target_affiliation: bool
	
	var projectile_position: Vector2
	var projectile_velocity: Vector2
	var projectile_age: float
	
	var _current_pierces_left: int = 0
	var _exclude_colliders: Array[RID] = [] #tracks what we've already hit to prevent double collision
	
	var vfx_instance: VFXInstance
	#cached objects
	var _raycast_query: PhysicsRayQueryParameters2D
	
	func _init(_hit_data: HitData, _delivery_data: DeliveryData):
		hit_data = _hit_data
		delivery_data = _delivery_data
		target_affiliation = hit_data.target_affiliation
		
		var source_position: Vector2
		if delivery_data.use_source_position_override: #if we use a custom override source position
			source_position = delivery_data.source_position #use the source position+
		else: #otherwise default to source's muzzle / overall position
			source_position = hit_data.source.attack_component.muzzle.global_position\
				if is_instance_valid(hit_data.source.attack_component.muzzle) else hit_data.source.global_position
		projectile_position = source_position
		
		_raycast_query = PhysicsRayQueryParameters2D.new()
		_raycast_query.collide_with_areas = true
		_raycast_query.collide_with_bodies = false
		_raycast_query.hit_from_inside = true
		
		CombatManager.simulated_projectiles.append(self)
		
	func start():
		var initial_velocity: Vector2
		if delivery_data.intercept_position and not delivery_data.use_initial_velocity_override:
			initial_velocity = (delivery_data.intercept_position - projectile_position).normalized() * delivery_data.projectile_speed
		else:
			initial_velocity = delivery_data.initial_velocity
		projectile_velocity = initial_velocity
		
		_current_pierces_left = delivery_data.pierce
		_exclude_colliders.append(hit_data.source.hitbox.get_rid())
		 #we manage lifetime and velocity by ourselves
		vfx_instance =  VFXManager.play_vfx(hit_data.vfx_on_spawn, projectile_position, Vector2.ZERO, VFXInfo.INFINITE_LIFETIME)
		
	func tick(delta: float):
		projectile_age += delta
		
		if is_instance_valid(hit_data.target): #slightly home towards intended target
			var desired_velocity: Vector2 = hit_data.target.global_position - projectile_position
			projectile_velocity = projectile_velocity.lerp(desired_velocity, base_homing * delta).normalized() * projectile_velocity.length()
		#physics and collision loop (handle multiple collisions/frame)
		var remaining_delta: float = delta
		var safety_break: int = 0
		while remaining_delta > 0.0 and safety_break < 10:
			safety_break += 1
			
			var start_pos := projectile_position
			var move_vec := projectile_velocity * remaining_delta
			var end_pos := start_pos + move_vec
			
			vfx_instance.position = projectile_position #vfx update
			
			# perform custom raycast
			var result = _perform_raycast(start_pos, end_pos)
			
			if result.is_empty(): #move to end
				projectile_position = end_pos
				break
			else:
				# hit something!
				var hit_pos := result.position as Vector2
				var collider := result.collider as Hitbox
				# advance projectile to hit point
				projectile_position = hit_pos
				# calculate fraction of delta consumed
				var dist_traveled: float = start_pos.distance_to(hit_pos)
				var dist_total: float = move_vec.length()
				var fraction: float = dist_traveled / dist_total if dist_total > 0.0 else 0.0
				remaining_delta -= (remaining_delta * fraction)
				# process the collision
				var stop_processing: bool = _handle_collision(collider, hit_pos)
				if stop_processing:
					return # projectile destroyed
				# if continuing (pierce), we must exclude this collider and nudge forward
				_exclude_colliders.append(result.rid)

		if projectile_age > delivery_data.projectile_lifetime and delivery_data.projectile_lifetime > 0.0: #timeout
			_on_destruct()

	func _perform_raycast(from: Vector2, to: Vector2) -> Dictionary:
		var space_state = References.island.get_world_2d().direct_space_state
		var query := _raycast_query
		
		query.from = from
		query.to = to
	
		var enemy_mask: int = Hitbox.get_mask(target_affiliation)
		query.collision_mask = enemy_mask
		
		if delivery_data.stop_on_walls:
			var wall_mask = Hitbox.get_mask(not target_affiliation)
			query.collision_mask = enemy_mask | wall_mask #combine two masks
			
		query.exclude = _exclude_colliders
	
		if _DEBUG: CombatManager._visualize_line_for_debug(from, to, 2.0, Color.RED)
		return space_state.intersect_ray(query)
		
	# returns TRUE if projectile should be destroyed
	func _handle_collision(hitbox: Hitbox, impact_pos: Vector2) -> bool:
		if not is_instance_valid(hitbox) or not is_instance_valid(hitbox.unit):
			return false # Hit something weird, ignore
			
		var unit: Unit  = hitbox.unit as Unit
		var stop_on_walls = delivery_data.stop_on_walls
		
		if not is_instance_valid(unit): #we hit something that isnt a unit's hitbox?
			push_warning("Invalid hitbox?")
			return false
	
		# allied/neutral structure/wall NOTE: if we do not stop on structures we shouldnt even detect them
		if unit is Tower: 
			if unit == hit_data.source:
				return false #ignore self
				
			if stop_on_walls:
				_apply_impact_vfx(impact_pos)
				_on_destruct(null) # wall hit = Death
				return true
			else:
				return false #pass through walls
	
		if unit.hostile == target_affiliation: # enemy
			_apply_hit_to_unit(unit, impact_pos)
			
			if _current_pierces_left > 0:
				_current_pierces_left -= 1
				return false # continue flying
			elif _current_pierces_left == -1:
				return false # infinite pierce
			else:
				_on_destruct(unit) # out of pierce charges
				return true
		return false #hit something allied that is not a structure (ignore)
	
	func _apply_hit_to_unit(unit: Unit, impact_pos: Vector2):
		_apply_impact_vfx(impact_pos)
		
		var hit_copy: HitData = hit_data.duplicate() as HitData #prevent mutation of original hitdata
		hit_copy.target = unit 

		if is_zero_approx(hit_data.radius):
			unit.take_hit(hit_copy)
		else:
			# trigger AOE at this point
			var units_in_aoe: Array[Unit] = CombatManager.get_units_in_radius(hit_data.radius, impact_pos, target_affiliation)
			for hit_unit: Unit in units_in_aoe:
				var aoe_hit: HitData = hit_data.duplicate() as HitData
				aoe_hit.target = hit_unit
				hit_unit.take_hit(aoe_hit)

	func _apply_impact_vfx(pos: Vector2):
		VFXManager.play_vfx(hit_data.vfx_on_impact, pos)
		Audio.play_sound(ID.Sounds.ENEMY_HIT_SOUND, pos)
	
	func _on_destruct(target: Unit = null):
		CombatManager.simulated_projectiles.erase(self)
		
		if is_instance_valid(vfx_instance):
			vfx_instance.delete = true
			
		Targeting.add_damage(hit_data.target, -hit_data.expected_damage)
			
func resolve_hit(hit_data: HitData, delivery_data: DeliveryData) -> void:
	var target: Unit = hit_data.target #this will be null if the hit does not have a predestined target
	var source: Unit = hit_data.source
	var source_position: Vector2
	if delivery_data.use_source_position_override: #if we use a custom override source position
		source_position = delivery_data.source_position #use the source position
	else: #otherwise default to source's muzzle / overall position
		source_position = hit_data.source.attack_component.muzzle.global_position\
			if is_instance_valid(hit_data.source.attack_component.muzzle) else hit_data.source.global_position
	var intercept_position: Vector2 = delivery_data.intercept_position
	#NOTE: this expected damage is for the projectile-in-flight regime
	#registered damage for the anticpiation regime must be deregistered before this
	Targeting.add_damage(hit_data.target, hit_data.expected_damage) #adds expected damage to target in targeting coordinator
	
	match delivery_data.delivery_method:
		DeliveryData.DeliveryMethod.HITSCAN:
			assert(is_instance_valid(target)) #WARNING: hitscan hits cannot be targetless
			#TODO: implement visuals
			target.take_hit(hit_data)
			Targeting.add_damage(hit_data.target, -hit_data.expected_damage)
		
		DeliveryData.DeliveryMethod.LINE_AOE:
			var space_state : PhysicsDirectSpaceState2D = source.get_world_2d().direct_space_state
			var query_params := PhysicsShapeQueryParameters2D.new()
			
			var line_vector = intercept_position - source_position
			var line_length = line_vector.length()
			# Use the hit's radius for the line's width.
			var line_width = hit_data.radius
			
			# Create a rectangle shape for the line query.
			var shape := RectangleShape2D.new()
			shape.size = Vector2(line_length, line_width)
			
			query_params.shape = shape
			# Position the query halfway along the line and rotate it to face the target.
			query_params.transform = Transform2D(line_vector.angle(), source_position + line_vector / 2.0)
			query_params.collide_with_areas = true
			query_params.collision_mask = Hitbox.get_mask(target.hostile)
			
			_visualize_shape_for_debug(shape, query_params.transform, 0.5) # visualize for 0.5 second

			var intersecting_colliders : Array[Dictionary] = space_state.intersect_shape(query_params)
			for collider_data : Dictionary in intersecting_colliders:
				var hitbox = collider_data.collider as Hitbox
				if not is_instance_valid(hitbox):
					continue
					
				var unit : Unit = hitbox.unit
				# Create a deep copy of the hit data for each target.
				#NOTE: we CANNOT pass by reference here, otherwise different units getting hit
				#would affect each other.
				var hit_copy: HitData = hit_data.duplicate()
				hit_copy.target = unit
				unit.take_hit(hit_copy)
			
			# Clean up the initial damage estimate for the primary target.
			Targeting.add_damage(target, -hit_data.expected_damage)

		DeliveryData.DeliveryMethod.CONE_AOE:
			var potential_targets : Array[Unit] = get_units_in_radius(hit_data.radius, source_position, hit_data.target_affiliation)
			if potential_targets.is_empty():
				return #no potential targets

			# Narrow-phase: Filter the units to find those within the cone's angle.
			var aim_direction : Vector2 = (intercept_position - source_position).normalized()
			var cone_half_angle_rad : float = deg_to_rad(delivery_data.cone_angle * 0.5)
			
			for unit: Unit in potential_targets:
				var to_target_direction : Vector2 = (unit.global_position - source_position).normalized()
				
				if not is_zero_approx(delivery_data.cone_angle):
					# use the dot product to check if the target is within the cone.
					var dot_product : float = aim_direction.dot(to_target_direction) #this equals to cos(t) where t is the angle betwee centreline and targetline
					if dot_product < cos(cone_half_angle_rad): #we are outside the cone
						continue
				
				var hit_copy = hit_data.duplicate()
				hit_copy.target = unit
				unit.take_hit(hit_copy)
		
			# clean up the initial damage estimate for the primary target.
			Targeting.add_damage(target, -hit_data.expected_damage)
		
		DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT:
			var resolver := ProjectileAbstractResolver.new(hit_data, delivery_data)
			resolver.start()
		
		DeliveryData.DeliveryMethod.PROJECTILE_SIMULATED:
			var resolver := ProjectileSimulatedResolver.new(hit_data, delivery_data)
			resolver.start()

var simulated_projectiles: Array[ProjectileSimulatedResolver] = [] #projectileresolvers will automatically add and remove themselves as necessary
func _process(_delta: float) -> void: #simulate all alive projectiles
	var delta: float = Clock.game_delta
	for simulated_projectile: ProjectileSimulatedResolver in simulated_projectiles:
		simulated_projectile.tick(delta)

func _visualize_shape_for_debug(shape: Shape2D, transform: Transform2D, duration: float, color: Color = Color.RED) -> void:
	# we need a canvas item to draw on. the root viewport is a good choice.
	var canvas: RID = References.island.get_canvas_item()
	# DisplayServer is the low-level server for all rendering.
	RenderingServer.canvas_item_add_set_transform(canvas, transform)
	
	# check the shape type and draw the appropriate primitive
	if shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = shape as RectangleShape2D
		var rect := Rect2(-rect_shape.size / 2.0, rect_shape.size) # center the rect on its origin
		RenderingServer.canvas_item_add_rect(canvas, rect, color)
	elif shape is CircleShape2D:
		var circle_shape: CircleShape2D = shape as CircleShape2D
		# a circle is drawn from its center, so its relative position is ZERO
		# when the transform is already at the desired center.
		RenderingServer.canvas_item_add_circle(canvas, Vector2.ZERO, circle_shape.radius, color)

	# create a timer to clear the drawing after the duration has passed
	get_tree().create_timer(duration).timeout.connect(
		func(): RenderingServer.canvas_item_clear(canvas)
	)
	
func _visualize_line_for_debug(from: Vector2, to: Vector2, width: float = -1.0, color = Color.RED, duration = INF) -> void:
	# we need a canvas item to draw on. the root viewport is a good choice.
	var canvas: RID = References.island.get_canvas_item()
	# check the shape type and draw the appropriate primitive
	RenderingServer.canvas_item_add_line(canvas, from, to, color, width)

	# create a timer to clear the drawing after the duration has passed
	get_tree().create_timer(duration).timeout.connect(
		func(): RenderingServer.canvas_item_clear(canvas)
	)
	
#helper functions
static var common_query_circle_shape := CircleShape2D.new() #using a common circleshape prevents unneccessary object creation
static func get_units_in_radius(radius: float, origin: Vector2, affiliation: bool, exclude_units: Array[Unit] = []) -> Array[Unit]:
	var circle_shape := common_query_circle_shape
	var space_state := References.island.get_world_2d().direct_space_state
	var query_params := PhysicsShapeQueryParameters2D.new()
	
	circle_shape.radius = radius
	query_params.shape = circle_shape
	query_params.collide_with_areas = true
	query_params.transform = Transform2D(0, origin)
	query_params.collision_mask = Hitbox.get_mask(affiliation)
	
	var hitboxes_in_aoe = space_state.intersect_shape(query_params, 2000)
	if _DEBUG: CombatManager._visualize_shape_for_debug(query_params.shape, query_params.transform, 0.5)
	
	var output_array: Array[Unit]
	for collision_data : Dictionary in hitboxes_in_aoe:
		var hitbox = collision_data.collider as Hitbox
		if not is_instance_valid(hitbox): #this filters out all non-hitbox detections
			continue
		
		if exclude_units.has(hitbox.unit):
			continue
			
		output_array.append(hitbox.unit)
	return output_array

static var common_raycast_query_params := PhysicsRayQueryParameters2D.new()
static func get_unit_along_ray(from: Vector2, to: Vector2, affiliation: bool, exclude_units: Array[Unit] = []) -> Unit:
	var space_state := References.island.get_world_2d().direct_space_state
	# use global coordinates, not local to node
	common_raycast_query_params.collide_with_areas = true
	common_raycast_query_params.collide_with_bodies = false
	common_raycast_query_params.collision_mask = Hitbox.get_mask(affiliation)
	common_raycast_query_params.from = from
	common_raycast_query_params.to = to
	
	if _DEBUG: CombatManager._visualize_line_for_debug(from, to, 2.0, Color.RED)
	
	var result: Dictionary = space_state.intersect_ray(common_raycast_query_params)
	if result.is_empty():
		return null

	var hitbox := result.collider as Hitbox
	if not is_instance_valid(hitbox):
		return null
		
	if exclude_units.has(hitbox.unit):
		return null
		
	return hitbox.unit
	
