extends Resource
class_name TowerData

@export var id: Towers.Type

#meta-properties
@export var size: Vector2i = Vector2i.ONE
@export var cost: float = 10.0
@export var required_capacity: float = 1.0
@export var max_level: int = 5
@export var element: Towers.Element

#navigation
@export var navcost: int = 10

@export var tower_name: String
@export_multiline var tower_description: String

@export var icon: Texture2D = preload("res://Assets/palisade.svg")
@export var tower_scene: PackedScene
#...upgrades
