extends Node

func resolve_hit(hit_data: HitData, delivery_data: DeliveryData):
	var target: Unit = hit_data.target
	var source: Unit = hit_data.source
	var intercept_position: Vector2 = delivery_data.intercept_position
	
	Targeting.add_damage(hit_data.target, hit_data.expected_damage) #adds expected damage to target in targeting coordinator
	
	match delivery_data.delivery_method:
		DeliveryData.DeliveryMethod.HITSCAN:
			target.take_hit(hit_data)
			Targeting.add_damage(hit_data.target, -hit_data.expected_damage)
		
		DeliveryData.DeliveryMethod.PROJECTILE_ABSTRACT:
			var intercept_time: float = (intercept_position - source.position).length() / delivery_data.projectile_speed
			
			#References.projectiles.marker_position = intercept_position
			#References.projectiles.queue_redraw()
			#
			var projectile: Sprite2D = preload("res://projectile.tscn").instantiate()
			projectile.position = source.position
			References.projectiles.add_child.call_deferred(projectile)
			
			var tween := create_tween()
			tween.tween_property(projectile, "position", intercept_position, intercept_time)
			
			await get_tree().create_timer(intercept_time).timeout
			if not is_instance_valid(target): return
			Targeting.add_damage(hit_data.target, -hit_data.expected_damage)
			
			projectile.queue_free()
			#References.projectiles.marker_position = Vector2(100000,10000)
			#References.projectiles.queue_redraw()
			
			if check_enemy_in_radius(intercept_position, 20.0, target):
				#print("intercepted with error: ", (intercept_position - target.position).length())
				target.take_hit(hit_data)
			else:
				pass
				#print("missed with error: ", (intercept_position - target.position).length())

func get_enemies_in_radius(center: Vector2, radius: float, max_results := 100) -> Array[Unit]:
	var space := References.island.get_world_2d().direct_space_state
	
	var shape := CircleShape2D.new()
	shape.radius = radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 0b0000_0001 #target only enemies

	var result := space.intersect_shape(query, max_results)
	var enemies: Array[Unit] = []

	for item in result:
		var collider = item["collider"]
		if collider == null:
			continue
		
		if not collider is Hitbox:
			continue
			
		if collider.unit == null:
			continue

		enemies.append(collider.unit)
	return enemies
	
func check_enemy_in_radius(center: Vector2, radius: float, target: Unit) -> bool:
	if not is_instance_valid(target):
		return false

	#var potential_targets := get_enemies_in_radius(center, radius)
	#var result: bool = false
	#for potential_target: Unit in potential_targets:
		#if potential_target == target:
			#result = true
			#break
			#
	#return result
	
	if (target.position - center).length_squared() > (radius * radius):
		return false
	else:
		return true
