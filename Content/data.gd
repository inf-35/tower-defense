extends Resource
class_name Data

signal value_changed(attribute: Attributes.id)

static func get_stringname(attribute: Attributes.id) -> StringName: #converts attributes.id to stringname
	match attribute:
		Attributes.id.MAX_HEALTH: #HealthData
			return StringName("max_health")
		Attributes.id.REGENERATION:
			return StringName("regeneration")
		Attributes.id.REGEN_PERCENT:
			return StringName("regen_percent")

		Attributes.id.MAX_SPEED: #MovementData
			return StringName("max_speed")
		Attributes.id.ACCELERATION:
			return StringName("acceleration")
		Attributes.id.TURN_SPEED:
			return StringName("turn_speed")

		Attributes.id.DAMAGE: #AttackData
			return StringName("damage")
		Attributes.id.RANGE:
			return StringName("range")
		Attributes.id.COOLDOWN:
			return StringName("cooldown")
		Attributes.id.RADIUS:
			return StringName("radius")
		_:
			return StringName("")

func resolve(attribute: Attributes.id) -> Variant: #converts attributes.id to stat access
	return return_or_null(get_stringname(attribute))

func return_or_null(stringname: StringName) -> Variant:
	return self.get(stringname) if stringname in self else null
