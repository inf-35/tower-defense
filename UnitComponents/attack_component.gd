extends UnitComponent
class_name AttackComponent
#polymorphic, stateless class that takes in AttackData and executes attacks
@export var attack_data: Data
var _modifiers_component: ModifiersComponent

func inject_components(modifiers_component: ModifiersComponent):
	_modifiers_component = modifiers_component
	_modifiers_component.register_data(attack_data)
	create_stat_cache(_modifiers_component, [Attributes.id.DAMAGE, Attributes.id.RADIUS, Attributes.id.COOLDOWN])

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
	hit_data.expected_damage = damage
	hit_data.modifiers = attack_data.generate_modifiers() #TODO: integrate hit modifiers with the modifiers system
	
	for modifier: Modifier in hit_data.modifiers:
		modifier.source_id = unit.unit_id

	unit.deal_hit(
		hit_data
	)

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
