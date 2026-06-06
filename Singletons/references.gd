extends Node
class_name References
#local logic signals
signal internal_references_ready()

#global logic signals
#NOTE: these signals should only be used when there is a true need for a "global scope"
@warning_ignore_start("unused_signal")
signal terrain_generating(parameters: GenerationParameters) ##fires before terrain generation, allows modification of generationparameters

#scene tree globals
var root: Node
var is_ready: bool = false

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

func start(active_island: Island = null) -> void:
	set_process(false)
	is_ready = false

	root = get_tree().get_root()
	if is_instance_valid(active_island):
		island = active_island
	elif root.has_node("Island"):
		island = root.get_node("Island")
	else:
		return
	#keep
	camera = island.get_node("Camera2D")
	tower_preview = island.get_node("TowerPreview")
	projectiles = island.get_node("Projectiles")
	path_renderer = island.get_node("PathRenderer")
	range_indicator = island.get_node("RangeIndicator")

	await get_tree().process_frame
	is_ready = true
	internal_references_ready.emit()
