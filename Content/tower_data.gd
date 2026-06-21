@tool
extends Resource
class_name TowerData


@export var target_type_name: String = "VOID"
@export_tool_button("submit tower type") var submit = submit_tower_type
func submit_tower_type() -> void:
	var clean_val = target_type_name.strip_edges().to_upper()

	#look up the enum dictionary
	if Towers.Type.has(clean_val):
		#valid! save the integer and the formatted string
		id = Towers.Type[clean_val]
		target_type_name = clean_val
	else:
		#invalid! reject the change or revert to void
		push_warning("Inspector: '" + target_type_name + "' is not a valid Towers.Type.")
		id = Towers.Type.VOID
		target_type_name = "VOID"
@export var id: Towers.Type

#meta-properties
@export var size: Vector2i = Vector2i.ONE
@export var cost: float = 10.0
@export var cost_scaling_override: float = INF ##0.05 = +5% per existing tower, INF uses the global default
@export var required_capacity: float = 1.0
@export var max_level: int = 5
@export var element: Towers.Element

@export var is_upgrade: bool = false ##is this tower type itself an upgrade
@export var is_rite: bool = false ##is this tower type a rite?
@export var is_environmental: bool = false ##is this tower type environmental? i.e. a forest
@export var upgrades_into: Dictionary[Towers.Type, float] = {} ##list of possible upgrades, where key is Type and value is cost (in gold)

@export var allowed_terrain: Array[Terrain.Base] = [] #if empty, allows all constructable terrains
#navigation
@export var navcost: int = 100

@export var tower_name: String
@export var rite_short_name: String = "" ##optional lower-friction label for rite-specific vfx such as "+drums"
@export_multiline var tower_description: String

@export var icon: Texture2D = preload("res://Assets/wall.png")
@export var preview: Texture2D = preload("res://Assets/ballista_whole.png")
@export var inspector_actions: Array[InspectorAction] = [preload("res://Content/InspectorActions/default_sell.tres"), preload("res://Content/InspectorActions/default_upgrade.tres")]
@export var tower_scene: PackedScene
#...upgrades
