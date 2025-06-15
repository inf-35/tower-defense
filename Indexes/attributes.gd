extends Node

enum id { #trackable value
	#health component
	MAX_HEALTH,
	REGENERATION,
	REGEN_PERCENT,
	#movement component
	MAX_SPEED,
	ACCELERATION,
	TURN_SPEED,
	#attack
	DAMAGE,
	RANGE,
	COOLDOWN,
	RADIUS,
}

enum Status { #diegetic statuses
	FROST,
	BURN,
	POISON,
}

class StatusEffectData:
	var attribute: id #what attribute is this status effect targeting
	
	var additive_per_stack: float = 0.0
	var multiplicative_per_stack: float = 0.0
	var can_stack: bool = true
	
	func _init(_attribute: id, _aps: float, _mps: float, _cs: bool = true):
		attribute = _attribute
		additive_per_stack = _aps
		multiplicative_per_stack = _mps
		can_stack = _cs

#NOTE to designers, these status effects should be normalised i.e. one stakc
#of FROST should be equivalent to one stack of POISON in importance
var status_effects : Dictionary[Status, StatusEffectData] = {
	Status.FROST: StatusEffectData.new(
		id.MAX_SPEED, 0.0, 0.7
	),
	Status.BURN: StatusEffectData.new(
		id.REGENERATION, -1, 0.0
	),
	Status.POISON: StatusEffectData.new(
		id.REGEN_PERCENT, -2, 0.0
	)
}
