extends Behavior
class_name SummonerBehavior

@export var spawn_unit_type: Units.Type = Units.Type.BASIC
@export var damage_per_unit_cost: float = 1.0 ## e.g., 50 Damage / 10 = 5 Units spawned
@export var spawn_radius: float = 15.0 ## how far from the host they appear
@export var max_spawn_count: int = 10 ## safety cap to prevent lag spikes

func start() -> void:
	super.start()

func update(_delta: float) -> void:
	#this tower doesnt attack in the usual way
	if attack_component.current_cooldown <= 0.0:
		#bypass attack()
		_perform_summoning()
		attack_component.current_cooldown = unit.get_stat(Attributes.id.COOLDOWN)

func _perform_summoning() -> void:
	if not is_instance_valid(unit):
		return

	var current_damage: float = unit.get_stat(Attributes.id.DAMAGE)
	# avoid division by zero or negative logic
	if current_damage <= 0 or damage_per_unit_cost <= 0:
		return
	var raw_count: int = floori(current_damage / damage_per_unit_cost)
	var final_count: int = clampi(raw_count, 1, max_spawn_count)

	_play_animation(&"cast") # requires 'cast' animation in the player
	ParticleManager.play_particles(ID.Particles.ENEMY_HIT_SPARKS, unit.global_position)

	var island = References.island
	if not is_instance_valid(island):
		return
		
	for i in final_count:
		var safety: int = 0
		var spawn_position: Vector2
		while safety < 10:
			var offset := Vector2.from_angle(randf() * TAU) * randf_range(0, spawn_radius) #small random enemy
			spawn_position = offset + unit.global_position
			var spawn_cell: Vector2i = Island.position_to_cell(spawn_position)
			if not Navigation.grid.has(spawn_cell):
				spawn_position = unit.global_position #CRITICAL: units should never fall out of the map!
				safety += 1
				continue

			if References.island.tower_grid.has(spawn_cell):
				var tower: Tower = References.island.tower_grid[spawn_cell]
				if tower.blocking:
					safety += 1
					continue
			
			Waves.spawn_enemy(spawn_unit_type, spawn_position)
			break

# override display data so we can see the current spawn rate in the debug inspector
func get_display_data() -> Dictionary:
	var current_dmg = unit.get_stat(Attributes.id.DAMAGE) if is_instance_valid(unit) else 0.0
	var count = floori(current_dmg / damage_per_unit_cost)
	return {
		"spawn_count": clampi(count, 1, max_spawn_count)
	}
