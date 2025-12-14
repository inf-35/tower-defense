extends Node

const _DEBUG: bool = true

class ProjectileAbstractResolver: #fire and forget delegate for ProjectileAbstract (see resolve_hit)
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
			source_position = delivery_data.source_position #use the source position
		else: #otherwise default to source's muzzle / overall position
			source_position = hit_data.source.attack_component.muzzle.global_position\
				if is_instance_valid(hit_data.source.attack_component.muzzle) else hit_data.source.global_position
	
	func start(delay : float):
		var source_to_target_normalized : Vector2 = (intercept_position - source_position).normalized()
		VFXManager.play_vfx(hit_data.vfx_on_spawn, source_position, delivery_data.projectile_speed * source_to_target_normalized, delay)
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

func resolve_hit(hit_data: HitData, delivery_data: DeliveryData):
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
			var potential_targets : Array[Unit] = get_units_in_radius(hit_data.radius, source_position, target.hostile)
			if potential_targets.is_empty():
				return #no potential targets
			
			# Narrow-phase: Filter the units to find those within the cone's angle.
			var aim_direction : Vector2 = (intercept_position - source_position).normalized()
			var cone_half_angle_rad : float = deg_to_rad(delivery_data.cone_angle * 0.5)
			
			for unit: Unit in potential_targets:
				var to_target_direction : Vector2 = (unit.global_position - source_position).normalized()
				
				# Use the dot product to check if the target is within the cone.
				var dot_product : float = aim_direction.dot(to_target_direction) #this equals to cos(t) where t is the angle betwee centreline and targetline
				if dot_product > cos(cone_half_angle_rad): #we are within the cone
					var hit_copy = hit_data.duplicate()
					hit_copy.target = unit
					unit.take_hit(hit_copy)
			
			# Clean up the initial damage estimate for the primary target.
			Targeting.add_damage(target, -hit_data.expected_damage)
		
		DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT:
			var intercept_time: float = (intercept_position - source_position).length() / delivery_data.projectile_speed
			if is_zero_approx((intercept_position - source_position).length()):
				intercept_time = 0.0
			var resolver := ProjectileAbstractResolver.new(hit_data, delivery_data)
			resolver.start(intercept_time)
			
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
