extends Control
class_name Inspector

@export var tower_overview : Control #tower overview:
@export var inspector_icon: TextureRect
@export var healthbar: ProgressBar

@export var inspector_title: Label
@export var subtitle: Label
@export var upgrade_button: Button
@export var sell_button: Button

@export var stats: GridContainer

@export var description: Label

@export var stats_per_line: int = 3

var inspector_mode: InspectorMode
var current_tower: Tower

enum InspectorMode {
	TowerOverview
}

func _ready():
	healthbar.value = 20.0
	healthbar.max_value = 200.0
	stats.columns = stats_per_line
	
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	sell_button.pressed.connect(_on_sell_button_pressed)

	UI.update_inspector_bar.connect(_on_inspector_contents_tower_update)
	UI.update_unit_state.connect(func(unit : Unit):
		if unit == current_tower: 
			_on_inspector_contents_tower_update(current_tower)
	)
	UI.update_unit_health.connect(func(unit : Unit, max_hp : float, hp : float):
		if unit == current_tower:
			_on_inspected_tower_health_update(current_tower, max_hp, hp)
	)

func _on_inspector_contents_tower_update(tower : Tower):
	stats.columns = stats_per_line
	
	current_tower = tower
	var tower_type : Towers.Type = tower.type

	inspector_title.text = Towers.get_tower_name(tower_type)
	subtitle.text = "mk" + str(tower.level) #TODO: implement localisation
	description.text = Towers.get_tower_description(tower_type)
	
	for child : Control in stats.get_children():
		child.free() #queue_free will cause bugs with get_child_count()
	
	# Get the list of display instructions from the tower's data resource
	var displays_to_create : Array[StatDisplayInfo] = tower.stat_displays
	# Loop through the instructions (in original order)
	#NOTE: DO NOT MUTATE displays_to_create
	for display_info : StatDisplayInfo in displays_to_create:
		_display_stat(tower, display_info)

func _on_inspected_tower_health_update(tower : Tower, max_hp : float, hp : float):
	healthbar.max_value = max_hp
	healthbar.value = hp
		

enum DisplayStatModifier {
	RECIPROCAL,
	CORE_FLUX,
	CAPACITY,
	LINE_BREAK,
	NONE,
	RETRIEVE_FIRST_ATTACK_STATUS_STACK,
	INVERT,
	CAPACITY_GENERATION,
	WAVES_LEFT_IN_PHASE
}

func _display_stat(tower: Tower, display_info: StatDisplayInfo):
	var value : Variant
	var override: bool = false
	
	# Handle special cases first
	match display_info.special_modifier:
		DisplayStatModifier.CORE_FLUX:
			override = true
			value = Player.flux

		DisplayStatModifier.CAPACITY:
			override = true
			value = Towers.get_tower_capacity(tower.type)
			#value = tower.get_intrinsic_effect_attribute(Effects.Type.CAPACITY_GENERATOR, &"capacity_generated")
			if value == null: return # Abort if this special stat isn't found
		
		DisplayStatModifier.CAPACITY_GENERATION:
			override = true
			value = tower.get_intrinsic_effect_attribute(Effects.Type.CAPACITY_GENERATOR, &"last_capacity_generation") ; CapacityGeneratorEffect
			if value == null: return

		DisplayStatModifier.LINE_BREAK:
			override = true
			value = null
			var spaces_to_add : int = stats_per_line - stats.get_child_count() % stats_per_line
			if spaces_to_add == stats_per_line: #we already have a line break anyways
				return
				
			for space_index : int in spaces_to_add:
				var space := Label.new()
				space.text = ""
				stats.add_child(space)
				
		DisplayStatModifier.RETRIEVE_FIRST_ATTACK_STATUS_STACK:
			override = true
			value = tower.attack_component.attack_data.status_effects[0].stack
			
		DisplayStatModifier.WAVES_LEFT_IN_PHASE:
			override = true
			# call the new, generic function on the unit.
			# the inspector does not know or care how the unit gets this data.
			value = tower.get_behavior_attribute(&"waves_left_in_phase")
			if value == null: return # abort if this special stat isn't found

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
	
	if display_info.special_modifier == DisplayStatModifier.INVERT:
		value *= -1
	
	if typeof(value) == TYPE_FLOAT: #round to 2dp
		value = roundi(value * 100) / 100

	var stat_label := Label.new()
	stat_label.text = display_info.label + " " + str(value) + display_info.suffix
	stats.add_child(stat_label)

func _on_upgrade_button_pressed():
	UI.place_tower_requested.emit(current_tower.type, current_tower.tower_position, current_tower.facing)
	
func _on_sell_button_pressed():
	UI.sell_tower_requested.emit(current_tower)
