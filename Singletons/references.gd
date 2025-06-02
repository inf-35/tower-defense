extends Node
#scene tree globals
@onready var root: Node = get_tree().get_root()

@onready var island: Island = root.get_node("Island")
@onready var camera: Camera2D = island.get_node("Camera2D")

var current_unit_id: int = -1
var current_stat_id: int = -1

func assign_unit_id() -> int:
	current_unit_id += 1
	return current_unit_id

func assign_stat_id() -> int:
	current_stat_id += 1
	return current_stat_id
