extends Node
#attributes singleton
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

	NULL,
	#NOTE: new effects are appended ad hoc to prevent disordering of exports
	DAMAGE_TAKEN, ##damage_taken (as a proportion from 0.0 to 1.0) (health component)
	FLAT_DAMAGE_TAKEN, ##flat damage additionally taken per hit
	REGEN_REMAINDER_PERCENT, ##regen taken as a percentage of remainder health
	ATTACK_RATE, ##flat attacks-per-second bonus used when resolving cooldown
	ARMOUR_IGNORE, ##fraction of negative flat damage taken ignored by outgoing hits
}

enum Status { #diegetic statuses
	FROST,
	BURN,
	POISON,
	HEAT,
	CURSED,
	BLEED,
	STUN,
	CLEANSE
}

class StatusAttributeData:
	var attribute: id #what attribute is this status effect targeting
	var additive_per_stack: float = 0.0
	var multiplicative_per_stack: float = 1.0

	func _init(_attribute: id, _aps: float, _mps: float) -> void:
		attribute = _attribute
		additive_per_stack = _aps
		multiplicative_per_stack = _mps

class StatusEffectData:
	var attributes: Array[StatusAttributeData] = []
	var can_stack: bool = true
	var overlay_color: Color = Color.TRANSPARENT

	func _init(_attributes: Array[StatusAttributeData], _cs: bool = true, _oc: Color = Color.TRANSPARENT) -> void:
		attributes = _attributes
		can_stack = _cs
		overlay_color = _oc

	func get_attribute_data(attribute: id) -> StatusAttributeData: ##returns the authored status row for this attribute, if present
		for attribute_data: StatusAttributeData in attributes:
			if attribute_data.attribute == attribute:
				return attribute_data

		return null

	func primary_attribute() -> id: ##returns the first authored attribute for legacy single-attribute callers
		if attributes.is_empty():
			return id.NULL

		return attributes[0].attribute

class ReactionData:
	var requisites: Dictionary[Status, float] #what statuses in what amount does this reaction need
	var effect: Callable #should have one argument (host unit)

	func _init(_requisites: Dictionary[Status, float], _effect: Callable) -> void:
		requisites = _requisites
		effect = _effect

#NOTE to designers, these status effects should be normalised i.e. one stack
#of FROST should be equivalent to one stack of POISON in importance/severity
var status_effects: Dictionary[Status, StatusEffectData] = {
	Status.FROST: StatusEffectData.new(
		[
			StatusAttributeData.new(id.MAX_SPEED, 0.0, 0.66),
			StatusAttributeData.new(id.COOLDOWN, 0.0, 1.0 / 0.66),
		],
		true,
		Color(0, 0, 1, 0.5)
	),
	Status.BURN: StatusEffectData.new(
		[StatusAttributeData.new(id.REGENERATION, -1, 1.0)],
		true,
		Color(1.0, 0.65, 0.0, 0.502) #-1 hp every second
	),
	Status.POISON: StatusEffectData.new(
		[StatusAttributeData.new(id.REGEN_REMAINDER_PERCENT, -0.05, 1.0)],
		true,
		Color(0, 1, 0, 0.5) #-5% remaining hp per second (capped at 2/s/stack)
	),
	Status.HEAT: StatusEffectData.new(
		[]  #this effect does nothing by itself, but reacts with FROST
	),
	Status.CURSED: StatusEffectData.new(
		[StatusAttributeData.new(id.DAMAGE_TAKEN, 0.0, 1.25)],
		true,
		Color(0.446, 0.002, 0.768, 0.5)
	),
	Status.BLEED: StatusEffectData.new(
		[StatusAttributeData.new(id.FLAT_DAMAGE_TAKEN, 0.5, 1.0)],
		true,
		Color(1,0,0,0.5),
	),
	Status.STUN: StatusEffectData.new(
		[StatusAttributeData.new(id.MAX_SPEED, 0.0, 0.2),
		StatusAttributeData.new(id.COOLDOWN, 0.0, 10.0),
		],
		false,
		Color(1, 1, 0.5) #80% mvmt reduction
	),
	Status.CLEANSE: StatusEffectData.new(
		[],
		false,
		Color(0.35, 0.65, 1.0, 0.35)
	)
}

const status_effect_icons: Dictionary[Status, Texture2D] = {
	Status.FROST: preload("res://Assets/frost_effect_icon.png"),
	Status.BURN: preload("res://Assets/burn_icon.png"),
	Status.CURSED: preload("res://Assets/cursed_icon.png"),
	Status.BLEED: preload("res://Assets/bleed_icon.png"),
	Status.POISON: preload("res://Assets/poison_icon.png"),
	Status.STUN: preload("res://Assets/stun_icon.png"),
	Status.CLEANSE: preload("res://Assets/healer.png")
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

static func get_icon(status: Attributes.Status) -> Texture2D:
	return status_effect_icons[status]
