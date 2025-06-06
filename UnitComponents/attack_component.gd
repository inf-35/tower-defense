extends UnitComponent
class_name AttackComponent
#polymorphic, stateless class that takes in AttackData and executes attacks
var attack_data: AttackData #"meta" attack resource - determines range, cooldown, etc.

var _modifiers_component: ModifiersComponent

func inject_components(modifiers_component: ModifiersComponent):
	_modifiers_component = modifiers_component
	_modifiers_component.register_data(attack_data)

func attack(target: Unit):
	if attack_data == null:
		return
	
	var radius: float = get_stat(_modifiers_component, attack_data, Attributes.id.RADIUS) #attack AoE
	
	if radius <= 0.01: #pointlike attack
		deal_attack(target)
	else: #aoe attack
		for unit: Unit in get_enemies_in_radius(target.movement_component.position, radius):
			deal_attack(unit)
	
	unit.draw_start = unit.position
	unit.draw_end = target.movement_component.position
	unit.draw_color = Color.CYAN

func deal_attack(target: Unit):
	var damage: float = get_stat(_modifiers_component, attack_data, Attributes.id.DAMAGE)

	var hit_data := HitData.new()
	hit_data.source = unit
	hit_data.target = target
	hit_data.damage = damage
	unit.deal_hit(
		hit_data
	)
	#
	#if attack_data.modifier_data != null:
		#target.modifiers_component.add_modifier(
			#Modifier.new(
				#attack_data.modifier_data.attribute,
				#attack_data.modifier_data.multiplicative,
				#attack_data.modifier_data.additive,
				#attack_data.modifier_data.override,
				#unit.unit_id
			#)
		#)

func get_enemies_in_radius(center: Vector2, radius: float, max_results := 100) -> Array[Unit]:
	var space := unit.get_world_2d().direct_space_state
	
	var shape := CircleShape2D.new()
	shape.radius = radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = 0b0000_0001

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
