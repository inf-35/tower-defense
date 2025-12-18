extends Resource
class_name Data

@warning_ignore("unused_signal") signal value_changed(attribute: Attributes.id)

static func get_stringname(attribute: Attributes.id) -> StringName: #converts attributes.id to stringname NOTE: this is to easily access variables in Data objects
	return StringName(str(Attributes.id.keys()[attribute]).to_lower()) #ie from DAMAGE_TAKEN -> damage_taken (which is the stringname used to access damage_taken in HealthData)

func resolve(attribute: Attributes.id) -> Variant: #converts attributes.id to stat access
	return return_or_null(get_stringname(attribute))

func return_or_null(stringname: StringName) -> Variant:
	return self.get(stringname) if stringname in self else null

func _init():
	pass
