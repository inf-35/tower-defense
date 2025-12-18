extends Node
#local logic signals
signal references_ready()

#global logic signals
#NOTE: these signals should only be used when there is a true need for a "global scope"
@warning_ignore_start("unused_signal")
signal terrain_generating(parameters: GenerationParameters) ##fires before terrain generation, allows modification of generationparameters

#scene tree globals
@onready var root: Node = get_tree().get_root()

@onready var island: Island = root.get_node("Island")
@onready var keep: Node
@onready var camera: Camera = island.get_node("Camera2D")
@onready var tower_preview: TowerPreview = island.get_node("TowerPreview")
@onready var projectiles: Node2D = island.get_node("Projectiles")

#global constants
const TOWER_GROUP: StringName = &"towers"
const HOSTILE_AFFILIATION: bool = true
const ALLIED_AFFILIATION: bool = false

#unit id management
var current_unit_id: int = -1
var current_stat_id: int = -1

func assign_unit_id() -> int:
	current_unit_id += 1
	return current_unit_id

func assign_stat_id() -> int:
	current_stat_id += 1
	return current_stat_id
	
func _ready():
	set_process(false)
	references_ready.emit()
