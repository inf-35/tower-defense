extends Control
class_name Inspector

@export var tower_overview : Control #tower overview:
@export var inspector_icon: TextureRect

@export var inspector_title: Label
@export var subtitle: Label
@export var upgrade_button: Button

@export var stats: GridContainer

@export var description: Label

var inspector_mode: InspectorMode

enum InspectorMode {
	TowerOverview
}

func _update_inspector_contents_tower(tower : Tower):
	pass
