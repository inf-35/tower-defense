extends RefCounted
class_name DeliveryData

enum DeliveryMethod {
	HITSCAN, #instant delivery to single target
	PROJECTILE_ABSTRACT, #abstract projectiles
	PROJECTILE_SIMULATED, #projectiles which have to be simulated (i.e. aoe, mid-way effects, etc.)
	CONE_AOE,
	LINE_AOE,
	ENTITY,
}

var target: Unit #reference to the actual target of this projectile
var intercept_position: Vector2 #predicted intercept position of described projectile
var tower_rotation: float #initial rotation of the tower (or whatever is firing this projectile)
var delivery_method: DeliveryMethod

#for projectiles
var projectile_speed: float #projectile speed across the 2d game plane
var initial_vertical_velocity: float #used for pseudo-3d projectiles, initial vertical velocity
var vertical_force: float #used for pseudo-3d projectiles, simulates gravity

#for coneAOE
var cone_angle : float #angle of the cone in degrees
