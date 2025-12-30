class_name UnitReplacedData extends EventData

var old_unit: Unit
var new_unit: Unit

func _init(old: Unit, new: Unit):
	old_unit = old
	new_unit = new
