extends Node

class ProjectileAbstractResolver: #fire and forget delegate for ProjectileAbstract (see resolve_hit)
	const ERROR_TOLERANCE : float = 15.0 #error tolerance for no AOE projectiles.
	const ERROR_TOLERANCE_SQUARED : float = ERROR_TOLERANCE ** 2 #length_squared optimisation
	
	static var circle_shape := CircleShape2D.new() #we share the same circleshape object across all checks
	static var timer_scene := SceneTree.new()
	
	var hit_data : HitData
	var delivery_data : DeliveryData
	var intercept_position : Vector2
	
	func _init(_hit_data: HitData, _delivery_data: DeliveryData):
		hit_data = _hit_data
		delivery_data = _delivery_data
		intercept_position = delivery_data.intercept_position
	
	func start(delay : float):
		var source_to_target_normalized : Vector2 = (hit_data.target.global_position - hit_data.source.global_position).normalized()
		VFXManager.play_vfx(hit_data.vfx_on_spawn, hit_data.source.global_position, delivery_data.projectile_speed * source_to_target_normalized, delay)
		CombatManager.get_tree().create_timer(delay).timeout.connect(func():
			_on_timeout()
		)
	
	func _on_timeout():
		VFXManager.play_vfx(hit_data.vfx_on_impact, intercept_position)
		var target : Unit = hit_data.target
		if not is_instance_valid(target): #if target is freed midway
			return #abort resolution

		Targeting.add_damage(hit_data.target, -hit_data.expected_damage) #remove expected damage
		if is_zero_approx(hit_data.radius): #this projectile has no aoe, so we just look for the primary target
			if (target.position - intercept_position).length_squared() > ERROR_TOLERANCE_SQUARED:
				return #we missed by over error tolerance
				
			target.take_hit(hit_data)
			return
		#if we reach here, the projectile has some aoe
		var space_state := target.get_world_2d().direct_space_state
		var query_params := PhysicsShapeQueryParameters2D.new()
		
		circle_shape.radius = hit_data.radius
		query_params.shape = circle_shape
		query_params.transform = Transform2D(0, intercept_position)
		query_params.collision_mask = Hitbox.get_mask(target.hostile)
		
		var hitboxes_in_aoe = space_state.intersect_shape(query_params)
		
		for collision_data : Dictionary in hitboxes_in_aoe:
			var hitbox_hit = collision_data.collider as Hitbox
			if not is_instance_valid(hitbox_hit):
				continue
				
			var unit_hit : Unit = hitbox_hit.unit
			var hit_copy = hit_data.duplicate(true)
			hit_copy.target = unit_hit
			unit_hit.take_hit(hit_copy)

func resolve_hit(hit_data: HitData, delivery_data: DeliveryData):
	var target: Unit = hit_data.target
	var source: Unit = hit_data.source
	var intercept_position: Vector2 = delivery_data.intercept_position
	
	Targeting.add_damage(hit_data.target, hit_data.expected_damage) #adds expected damage to target in targeting coordinator
	
	match delivery_data.delivery_method:
		DeliveryData.DeliveryMethod.HITSCAN:
			target.take_hit(hit_data)
			Targeting.add_damage(hit_data.target, -hit_data.expected_damage)
		
		DeliveryData.DeliveryMethod.LINE_AOE:
			var space_state : PhysicsDirectSpaceState2D = source.get_world_2d().direct_space_state
			var query_params := PhysicsShapeQueryParameters2D.new()
			
			var line_vector = intercept_position - source.global_position
			var line_length = line_vector.length()
			# Use the hit's radius for the line's width.
			var line_width = hit_data.radius
			
			# Create a rectangle shape for the line query.
			var shape := RectangleShape2D.new()
			shape.size = Vector2(line_length, line_width)
			
			query_params.shape = shape
			# Position the query halfway along the line and rotate it to face the target.
			query_params.transform = Transform2D(line_vector.angle(), source.global_position + line_vector / 2.0)
			query_params.exclude = [source.get_rid()]
			query_params.collision_mask = Hitbox.get_mask(target.hostile)
			
			var intersecting_colliders : Array[Dictionary] = space_state.intersect_shape(query_params)
			for collider_data : Dictionary in intersecting_colliders:
				var hitbox = collider_data.collider as Hitbox
				if not is_instance_valid(hitbox):
					continue
					
				var unit : Unit = hitbox.unit
				# Create a deep copy of the hit data for each target.
				#NOTE: we CANNOT pass by reference here, otherwise different units getting hit
				#would affect each other.
				var hit_copy = hit_data.duplicate(true)
				hit_copy.target = unit
				unit.take_hit(hit_copy)
			
			# Clean up the initial damage estimate for the primary target.
			Targeting.add_damage(target, -hit_data.expected_damage)

		DeliveryData.DeliveryMethod.CONE_AOE:
			var space_state : PhysicsDirectSpaceState2D = source.get_world_2d().direct_space_state
			var query_params := PhysicsShapeQueryParameters2D.new()
			
			# Broad-phase: Find all units within a circle defined by the attack range.
			var shape := CircleShape2D.new()
			shape.radius = hit_data.range
			
			query_params.shape = shape
			query_params.transform = Transform2D(0.0, source.global_position)
			query_params.exclude = [source.get_rid()]
			query_params.collision_mask = Hitbox.get_mask(target.hostile)
			
			var potential_targets : Array[Dictionary] = space_state.intersect_shape(query_params)
			if potential_targets.is_empty():
				return #no potential targets
			
			# Narrow-phase: Filter the units to find those within the cone's angle.
			var aim_direction : Vector2 = (intercept_position - source.global_position).normalized()
			var cone_half_angle_rad : float = deg_to_rad(delivery_data.cone_angle * 0.5)
			
			for collider_data : Dictionary in potential_targets:
				var hitbox = collider_data.collider as Hitbox
				if not is_instance_valid(hitbox):
					continue
					
				var unit : Unit = hitbox.unit
				var to_target_direction : Vector2 = (unit.global_position - source.global_position).normalized()
				
				# Use the dot product to check if the target is within the cone.
				var dot_product : float = aim_direction.dot(to_target_direction) #this equals to cos(t) where t is the angle betwee centreline and targetline
				if dot_product > cos(cone_half_angle_rad): #we are within the cone
					var hit_copy = hit_data.duplicate(true)
					hit_copy.target = unit
					unit.take_hit(hit_copy)
			
			# Clean up the initial damage estimate for the primary target.
			Targeting.add_damage(target, -hit_data.expected_damage)
		
		DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT:
			var intercept_time: float = (intercept_position - source.position).length() / delivery_data.projectile_speed
			#TODO: implement graphics here
			var resolver := ProjectileAbstractResolver.new(hit_data, delivery_data)
			resolver.start(intercept_time)
