extends Resource
class_name TowerData

@export var id: Towers.Type

#meta-properties
@export var size: Vector2i = Vector2i.ONE
@export var cost: float = 10.0
@export var required_capacity: float = 1.0
@export var max_level: int = 5
@export var element: Towers.Element

@export var is_upgrade: bool = false ##is this tower type itself an upgrade
@export var is_rite: bool = false ##is this tower type a rite?
@export var upgrades_into: Dictionary[Towers.Type, float] = {} ##list of possible upgrades, where key is Type and value is cost (in gold)

#navigation
@export var navcost: int = 100

@export var tower_name: String
@export_multiline var tower_description: String

@export var icon: Texture2D = preload("res://Assets/wall.png")
@export var preview: Texture2D = preload("res://Assets/ballista_whole.png")
@export var inspector_actions: Array[InspectorAction] = [preload("res://Content/InspectorActions/default_sell.tres"), preload("res://Content/InspectorActions/default_upgrade.tres")]
@export var tower_scene: PackedScene
#...upgrades
