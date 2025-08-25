extends Resource
class_name TowerData

@export var id: Towers.Type

#meta-properties
@export var cost: float = 10.0
@export var required_capacity: float = 1.0
@export var max_level: int = 5
@export var element: Towers.Element

@export var tower_name: String
@export var tower_description: String

@export var tower_scene: PackedScene
#...upgrades
