extends Area2D
class_name Hitbox

var unit: Unit #unit to which this hitbox belongs to (automatically set by unit.gd)

func _ready() -> void: ##registers hitboxes for diagnostic counting without changing collision participation
	add_to_group(DebugAssistant.GROUP_HITBOXES)
	monitoring = false

static func get_mask(hostile: bool = true) -> int: #for getting collision masks
	return 0b01 if hostile else 0b10
