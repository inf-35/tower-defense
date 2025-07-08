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
	
	_display_stat(tower, Attributes.id.NULL, "BPS", "", [DisplayStatModifier.HARVESTER_BLUEPRINTS_PER_WAVE])
	_display_stat(tower, Attributes.id.NULL, "FLUX", "", [DisplayStatModifier.CORE_FLUX])
	_display_stat(tower, Attributes.id.DAMAGE, "DMG")
	_display_stat(tower, Attributes.id.COOLDOWN, "HIT", "/s", [DisplayStatModifier.RECIPROCAL])
	_display_stat(tower, Attributes.id.RANGE, "RNG")
	_display_stat(tower, Attributes.id.MAX_HEALTH, "MAX HP")
	_display_stat(tower, Attributes.id.REGENERATION, "RGN")

enum DisplayStatModifier {
	RECIPROCAL,
	CORE_FLUX,
	HARVESTER_BLUEPRINTS_PER_WAVE,
}

func _display_stat(tower : Tower, attribute : Attributes.id, prefix : String = "", suffix : String = "", modifiers : Array[DisplayStatModifier] = []):
	var value
	var override : bool = false
	
	if modifiers.has(DisplayStatModifier.CORE_FLUX):
		override = true
		value = Player.flux
		
	if modifiers.has(DisplayStatModifier.HARVESTER_BLUEPRINTS_PER_WAVE):
		override = true
		value = tower.get_intrinsic_effect_attribute(Effects.Type.BLUEPRINT_ON_WAVE, "blueprints_per_wave"); WaveBlueprintEffect
		#see WaveBlueprintEffect
		if value == null: #not harvester or malformed harvester
			return #abort
	
	if (not override) and tower.modifiers_component.has_stat(attribute):
		value = tower.modifiers_component.pull_stat(attribute) #for existing towers
	elif (not override) and Towers.get_tower_stat(tower.type, attribute):
		value = Towers.get_tower_stat(tower.type, attribute) #for tower previews
	
	if value == null:
		return
		
	if modifiers.has(DisplayStatModifier.RECIPROCAL):
		value = 1.0 / value
	
	if typeof(value) == TYPE_FLOAT:
		value = round(value * 100) / 100 #round float values to 2dp

	var stat_label : Label = Label.new()
	stat_label.text = prefix + " " + str(value) + suffix
	stats.add_child(stat_label)
