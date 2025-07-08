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
var current_tower: Tower

enum InspectorMode {
	TowerOverview
}

func _ready():
	UI.update_inspector_bar.connect(_on_inspector_contents_tower_update)
	UI.update_unit_state.connect(func(unit : Unit):
		if unit == current_tower: _on_inspector_contents_tower_update(current_tower)
	)

func _on_inspector_contents_tower_update(tower : Tower):
	current_tower = tower
	var tower_type : Towers.Type = tower.type

	inspector_title.text = Towers.get_tower_name(tower_type)
	subtitle.text = "mk" + str(tower.level) #TODO: implement localisation
	description.text = Towers.get_tower_description(tower_type)
	
	for child : Control in stats.get_children():
		child.free()
	
	if tower.modifiers_component.has_stat(Attributes.id.DAMAGE):
		var damage_label : Label = Label.new()
		damage_label.text = "DMG " + str(tower.modifiers_component.pull_stat(Attributes.id.DAMAGE))
		stats.add_child(damage_label)
	else:
		print("no retrieval")
		
