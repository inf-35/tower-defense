extends Node
#local logic signals
signal references_ready()

#global logic signals
#NOTE: these signals should only be used when there is a true need for a "global scope"
@warning_ignore_start("unused_signal")
signal terrain_generating(parameters: GenerationParameters) ##fires before terrain generation, allows modification of generationparameters

#scene tree globals
var root: Node

var island: Island
var keep: Node
var camera: Camera
var tower_preview: TowerPreview
var path_renderer: PathRenderer
var range_indicator: RangeIndicator
var projectiles: Node2D

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
	
func start():
	set_process(false)

	root = get_tree().get_root()
	island = root.get_node("Island")
	#keep
	camera = island.get_node("Camera2D")
	tower_preview = island.get_node("TowerPreview")
	projectiles = island.get_node("Projectiles")
	path_renderer = island.get_node("PathRenderer")
	range_indicator = island.get_node("RangeIndicator")
	
	await get_tree().process_frame
	references_ready.emit()
