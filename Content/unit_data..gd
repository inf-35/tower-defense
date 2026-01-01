extends Resource
class_name UnitData

@export var title: String
@export_multiline var description: String
@export var stat_displays: Array[StatDisplayInfo] = []

@export var unit_scene: PackedScene

@export var flux_value: float = 0.5 ## base flux dropped on death
@export var strength_value: float = 1.0 ## used for director/difficulty calculation
