extends RefCounted
class_name DeliveryData ##describes the in-flight trajectory of a projectile

enum DeliveryMethod {
	HITSCAN, #instant delivery to single target
	PROJECTILE_ABSTRACT, #abstract projectiles
	PROJECTILE_SIMULATED, #projectiles which have to be simulated (i.e. aoe, mid-way effects, etc.)
	CONE_AOE,
	LINE_AOE,
	ENTITY,
}

var target: Unit ##reference to the actual target of this projectile
var excluded_units: Array[Unit] ## units that are excluded (mainly from non-targeted projectiles)
var use_source_position_override: bool = false ##if true, enables source_position override
var source_position: Vector2 ##custom source position. if use_source_position_override is true, oversrides source (from HitData)'s position
var use_initial_velocity_override: bool = false ##if true, uses initial_velocity
var initial_velocity: Vector2 ##otherwise just calclculates it from target
var intercept_position: Vector2 ##predicted intercept position of described projectile
var tower_rotation: float ##initial rotation of the tower (or whatever is firing this projectile)
var delivery_method: DeliveryMethod ##delivery method. see CombatManager

#for projectiles
var projectile_speed: float ##projectile speed across the 2d game plane
var initial_vertical_velocity: float ##used for pseudo-3d projectiles, initial vertical velocity
var vertical_force: float ##used for pseudo-3d projectiles, simulates gravity

#extension: for simulated projectiles
var projectile_lifetime: float = 0.0 ##lifetime of the projectile, after which the projectile will despawn
var pierce: int = 0 ##how many enemies can this projectile pass through? (-1 = infinite)
var stop_on_walls: bool = false ##does the projectile stop at walls?

#for coneAOE
var cone_angle : float ##angle of the fire cone in degrees
