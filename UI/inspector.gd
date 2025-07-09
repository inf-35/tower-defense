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
		child.queue_free()
	
	# Get the list of display instructions from the tower's data resource
	var displays_to_create : Array[StatDisplayInfo] = tower.stat_displays
	# Loop through the instructions (in original order)
	#NOTE: DO NOT MUTATE displays_to_create
	for display_info : StatDisplayInfo in displays_to_create:
		_display_stat(tower, display_info)
		

enum DisplayStatModifier {
	RECIPROCAL,
	CORE_FLUX,
	HARVESTER_BLUEPRINTS_PER_WAVE,
	LINE_BREAK,
	NONE,
}

	
func _display_stat(tower: Tower, display_info: StatDisplayInfo):
	var value : Variant
	var override: bool = false
	
	print("Processing stat with label " ,  display_info.label)
	
	# Handle special cases first
	match display_info.special_modifier:
		DisplayStatModifier.CORE_FLUX:
			override = true
			value = Player.flux
		DisplayStatModifier.HARVESTER_BLUEPRINTS_PER_WAVE:
			override = true
			value = tower.get_intrinsic_effect_attribute(Effects.Type.BLUEPRINT_ON_WAVE, &"blueprints_per_wave")
			if value == null: return # Abort if this special stat isn't found
	
	# Get the value from the tower's components if not overridden
	if not override:
		var attribute = display_info.attribute
		if tower.modifiers_component and tower.modifiers_component.has_stat(attribute):
			value = tower.modifiers_component.pull_stat(attribute)
		elif Towers.get_tower_stat(tower.type, attribute): # Fallback for previews
			value = Towers.get_tower_stat(tower.type, attribute)

	if value == null:
		return # Don't display if no value could be found
		
	# Apply final modifiers
	if display_info.special_modifier == DisplayStatModifier.RECIPROCAL and value != 0:
		value = 1.0 / value
	
	if typeof(value) == TYPE_FLOAT:
		value = round(value * 100) / 100

	var stat_label := Label.new()
	stat_label.text = display_info.label + " " + str(value) + display_info.suffix
	stats.add_child(stat_label)
