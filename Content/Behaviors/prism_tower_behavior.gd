extends Behavior
class_name PrismBehavior

const PRISM_LASER_SCENE: PackedScene = preload("res://Units/Towers/prism/prism_laser.tscn")

var _lasers_by_partner: Dictionary[Tower, Node] = {}

func start() -> void:
	assert(unit is Tower)
	TowerNetworkManager.register_tower(unit, TowerNetworkManager.NetworkType.PRISM, self)
	unit.died.connect(_on_death)
	
#called by TowerNetworkManager (we are the handler)
func create_link(partner: Tower):
	print(partner)
	_create_prism_laser(partner)
	pass
	
func remove_link(partner: Tower):
	print(partner, " removed!")
	_remove_prism_laser(partner)
	
func _create_prism_laser(prism_b: Tower) -> void:
	var prism_a: Tower = unit #host tower
	var laser: PrismLaser = PRISM_LASER_SCENE.instantiate()
	laser.prism_a = prism_a
	laser.prism_b = prism_b
	_lasers_by_partner[prism_b] = laser
	References.island.add_child.call_deferred(laser)
	
	# configure the laser's damage from the prism's attack data
	laser.hit_data_prototype = prism_a.attack_component.attack_data.generate_hit_data()
	laser.cooldown = prism_a.attack_component.attack_data.cooldown
	#TODO: make it such that the stats are the average of both towers
	
	# position and rotate the laser's Area2D
	var pos_a_world: Vector2 = Island.cell_to_position(prism_a.tower_position)
	var pos_b_world: Vector2 = Island.cell_to_position(prism_b.tower_position)
	var vector: Vector2 = pos_b_world - pos_a_world
	
	laser.global_position = pos_a_world + vector / 2.0
	laser.rotation = vector.angle()
	
	# scale the collision shape to fit the distance
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(vector.length(), 8) # 10 is the laser width
	laser.collision_shape.shape = shape

func _remove_prism_laser(prism_b: Tower) -> void:
	_lasers_by_partner[prism_b].queue_free()
	_lasers_by_partner.erase(prism_b)

func _on_death():
	TowerNetworkManager.deregister_tower(unit, TowerNetworkManager.NetworkType.PRISM)

# the breach has no active behavior in its _process loop, so update is empty
func update(_delta: float) -> void:
	pass
	
#func get_display_data() -> Dictionary:
	## we use StringNames (&) for performance and to avoid typos.
	#if _waves_left_in_state == 0: #not initialised
		#return { #for preview inspection
			#ID.UnitState.WAVES_LEFT_IN_PHASE: seed_duration_waves
		#}
#
	#return {
		#ID.UnitState.WAVES_LEFT_IN_PHASE: _waves_left_in_state
	#}
