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
	
	NULL
}

enum Status { #diegetic statuses
	FROST,
	BURN,
	POISON,
	HEAT,
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

class ReactionData:
	var requisites: Dictionary[Status, float] #what statuses in what amount does this reaction need
	var effect: Callable #should have one argument (host unit)
	
	func _init(_requisites: Dictionary[Status, float], _effect: Callable):
		requisites = _requisites
		effect = _effect

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
	),
	Status.HEAT: StatusEffectData.new(
		id.MAX_SPEED, 0.0, 1.0  #this effect does nothing by itself, but reacts with FROST 
	),
}

var reactions: Array[ReactionData] = [
	ReactionData.new(
		{Status.FROST: 1.0, Status.HEAT: 1.0},
		generate_damage_callable(200.0)
	)
]

#a list of just standard reaction effects. they should all take in unit as sole parameter, see ModifiersComponent check_reactions_for_status()
static func generate_damage_callable(dmg: float) -> Callable:
	return func(unit: Unit):
		var hit_data := HitData.new()
		hit_data.damage = dmg
		hit_data.expected_damage = dmg
		hit_data.source = unit #source is self (by convention)
		hit_data.target = unit
		
		unit.take_hit(hit_data)
		
