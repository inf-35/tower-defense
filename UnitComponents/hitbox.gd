extends Area2D
class_name Hitbox

var unit: Unit #unit to which this hitbox belongs to (automatically set by unit.gd)

static func get_mask(hostile: bool = true) -> int: #for getting collision masks
	return 0b01 if hostile else 0b10
