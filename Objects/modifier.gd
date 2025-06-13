extends RefCounted
class_name Modifier #raw attribute modifying effects

var attribute: Attributes.id = Attributes.id.MAX_HEALTH #non-diegetic (ie max_health, movement_speed etc.)
var status: Attributes.Status #diegetic status (ie frost, poison, fire etc.)
	
var additive: float = 0.0
var multiplicative: float = 1.0 #multiplicative (ie * 1.0)
var override = null #overrides all values, basically sets the attribute to this value

var source_id: int #unit id of the source of this modifier

var cooldown: float = -1.0 #negative cooldown -> permanent

func _init(_attribute: Attributes.id, _status: Attributes.Status, _multiplicative: float = 1.0, _additive: float = 0.0, _override = null, _source_id = 0) -> void:
	attribute = _attribute
	status = _status
	additive = _additive
	multiplicative = _multiplicative
	override = _override
	source_id = _source_id
