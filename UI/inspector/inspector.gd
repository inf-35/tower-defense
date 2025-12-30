extends Control
class_name Inspector

@export var tower_overview : Control #tower overview:
@export var inspector_icon: TextureRect
@export var healthbar: ProgressBar

@export var inspector_title: Label
@export var subtitle: Label
@export var status_container: HBoxContainer
@export var button_container: HBoxContainer
@export var action_button_scene: PackedScene

@export var stats: GridContainer

@export var description: InteractiveRichTextLabel

@export var stats_per_line: int = 3

var inspector_mode: InspectorMode
var current_tower: Tower

enum InspectorMode {
	TowerOverview
}

func _ready():
	healthbar.min_value = 0.0
	stats.columns = stats_per_line
	
	#upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	#sell_button.pressed.connect(_on_sell_button_pressed)

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
	
	if tower != current_tower: #this is a new tower being switched to
		tower.on_event.connect(func(event: GameEvent):
			if event.event_type != GameEvent.EventType.REPLACED:
				return
				
			var data := event.data as UnitReplacedData
			if data.old_unit == current_tower:
				_on_inspected_tower_replaced(current_tower, data.new_unit as Tower)
		)
	
	current_tower = tower
	var tower_type : Towers.Type = tower.type
	
	inspector_icon.texture = Towers.get_tower_icon(tower_type)

	inspector_title.text = Towers.get_tower_name(tower_type)
	subtitle.text = "mk" + str(tower.level) #TODO: implement localisation
	description.set_parsed_text(Towers.get_tower_description(tower_type))
	
	for child : Control in stats.get_children():
		child.free() #queue_free will cause bugs with get_child_count()
	
	# Get the list of display instructions from the tower's data resource
	var displays_to_create : Array[StatDisplayInfo] = tower.stat_displays
	# Loop through the instructions (in original order)
	#NOTE: DO NOT MUTATE displays_to_create
	for display_info : StatDisplayInfo in displays_to_create:
		_display_stat(tower, display_info)
	
	tower.get_unit_state() #this prompts the tower to send us its health too
	
	_refresh_actions(tower)
	_update_status_display(tower)
	
func _refresh_actions(tower: Tower) -> void:
	# clear existing buttons
	for child: Node in button_container.get_children():
		child.queue_free()
	#print("Clear!")
	
	#get actions from data
	var actions: Array[InspectorAction] = Towers.get_tower_actions(tower.type)
	#print("Inspector: length of actions: ", len(actions), " caused by ", Towers.Type.keys()[tower.type])
	for action: InspectorAction in actions:
		_create_action_button(tower, action)
	
func _create_action_button(tower: Tower, action: InspectorAction) -> void:
	var btn := action_button_scene.instantiate() as Button
	button_container.add_child(btn)
	
	btn.text = action.label
	btn.icon = action.icon
	
	var is_disabled: bool = false
	
	match action.type:
		InspectorAction.ActionType.UPGRADE:
			var upgrades := Towers.get_tower_upgrades(tower.type)
			if upgrades.size() <= action.upgrade_index:
				is_disabled = true # no upgrade available
			else:
				var next_type: Towers.Type = upgrades[action.upgrade_index]
				var cost := Towers.get_tower_upgrade_cost(tower.type, next_type)
				btn.text += " (%d)" % cost
				if Player.flux < cost:
					is_disabled = true
					
				btn.pressed.connect(UI.upgrade_tower_requested.emit.bind(tower, next_type))
		
		InspectorAction.ActionType.SELL:
			var sell_value: float = roundi(tower.flux_value * 10) * 0.1
			btn.text += " (%d)" % sell_value
			btn.pressed.connect(UI.sell_tower_requested.emit.bind(tower))
			
	btn.disabled = is_disabled

func _on_inspected_tower_health_update(tower : Tower, max_hp : float, hp : float):
	healthbar.max_value = max_hp
	healthbar.value = hp
	
	_update_status_display(tower)

func _on_inspected_tower_replaced(_old_tower: Tower, new_tower: Tower):
	print("replaced!")
	_on_inspector_contents_tower_update(new_tower)
	
enum DisplayStatModifier {
	RECIPROCAL,
	CORE_FLUX,
	CAPACITY,
	LINE_BREAK,
	NONE,
	RETRIEVE_FIRST_ATTACK_STATUS_STACK,
	INVERT,
	CAPACITY_GENERATION,
	WAVES_LEFT_IN_PHASE,
	ANOMALY_REWARD_PREVIEW,
}

func _update_status_display(tower: Tower) -> void:
	if not is_instance_valid(status_container):
		return

	# 1. Clear existing icons
	for child in status_container.get_children():
		child.queue_free()
	
	if not is_instance_valid(tower):
		return

	# 2. Check "Dead" Status
	# We prioritize this as the first icon if valid
	if is_instance_valid(tower.health_component):
		if tower.health_component.health <= 0:
			# You can add a "DEAD" entry to KeywordService or hardcode it here
			var dead_icon := preload("res://Assets/wall.png") # Replace with your asset
			_create_status_widget(dead_icon, "Destroyed", "This tower is destroyed and thus disabled. Will revive next wave if not sold.", 0, true)
	
	# 3. Check Modifiers/Status Effects
	if is_instance_valid(tower.modifiers_component):
		# We access the internal dictionary. 
		# Ideally ModifiersComponent would expose: func get_active_statuses() -> Dictionary
		var effects: Dictionary = tower.modifiers_component._status_effects
		
		for status_enum in effects:
			var instance = effects[status_enum]
			if instance.stack <= 0: 
				continue
			
			# Resolve Data via KeywordService
			# We convert the Enum (e.g. 5) to String Key (e.g. "FROST")
			var status_key: String = Attributes.Status.keys()[status_enum]
			var data: Dictionary = KeywordService.get_keyword_data(status_key)
			
			# Fallback if KeywordService doesn't have data for this status yet
			var icon = data.get("icon", null)
			var title = data.get("title", status_key.capitalize())
			var desc = data.get("description", "")
			
			_create_status_widget(icon, title, desc, instance.stack)

func _create_status_widget(icon: Texture2D, title: String, desc: String, stacks: float, is_negative_state: bool = false) -> void:
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(32, 32) # Standard Icon Size
	
	var tex = TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	if icon:
		tex.texture = icon
	else:
		# Debug fallback
		var p = PlaceholderTexture2D.new()
		p.size = Vector2(32, 32)
		tex.texture = p
		
	if is_negative_state:
		tex.modulate = Color(1, 0.4, 0.4) # Red tint for death
		
	wrapper.add_child(tex)
	
	# Stack Count Label
	if stacks > 1:
		var lbl = Label.new()
		lbl.text = str(int(stacks))
		# Position at bottom-right
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.position -= Vector2(8, 0) # Small offset
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		wrapper.add_child(lbl)
		
	wrapper.mouse_entered.connect(func():
		var tooltip_data: Dictionary = {
			"title": title,
			"description": desc,
			"icon": icon,
		}
		
		var tooltip_instance: TooltipPanel = KeywordService.TOOLTIP_PANEL.instantiate()
		add_child(tooltip_instance)
		tooltip_instance.show_tooltip(tooltip_data)
		wrapper.set_meta(&"active_tooltip", tooltip_instance)
	)
	
	wrapper.mouse_exited.connect(func():
		if wrapper.has_meta(&"active_tooltip"):
			var tooltip_instance: TooltipPanel = wrapper.get_meta(&"active_tooltip")
			
			if is_instance_valid(tooltip_instance):
				# CRITICAL: do NOT call queue_free() directly
				# call on_link_mouse_exited(), which triggers the "Grace Period" logic
				# allowing the player to move their mouse FROM the icon INTO the tooltip
				# to read nested keywords
				tooltip_instance.on_link_mouse_exited()

			wrapper.remove_meta(&"active_tooltip")
	)
	
	status_container.add_child(wrapper)

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
			if value == null: return # abort if this special stat isn't found
		
		DisplayStatModifier.CAPACITY_GENERATION:
			override = true
			value = tower.get_intrinsic_effect_attribute(Effects.Type.CAPACITY_GENERATOR, &"last_capacity_generation") #see CapacityGeneratorEffect
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
			value = tower.get_behavior_attribute(ID.UnitState.WAVES_LEFT_IN_PHASE)
			#used by any tower which has a wave-based state i.e. anomaly, breach, etc.
			if value == null: return # abort if this special stat isn't found
			
		DisplayStatModifier.ANOMALY_REWARD_PREVIEW:
			override = true
			var waves_left_to_reward: int = tower.get_behavior_attribute(ID.UnitState.WAVES_LEFT_IN_PHASE)
			var reward: Reward = tower.get_behavior_attribute(ID.UnitState.REWARD_PREVIEW)
			
			if reward.type == Reward.Type.ADD_RELIC:
				value = reward.relic.title + " in " + str(waves_left_to_reward) + " waves."
			elif reward.type == Reward.Type.UNLOCK_TOWER:
				value = Towers.get_tower_name(reward.tower_type) + " in " + str(waves_left_to_reward) + " waves."
			elif reward.type == Reward.Type.ADD_RITE:
				value = Towers.get_tower_name(reward.rite_type) + " in " + str(waves_left_to_reward) + " waves."
		
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
		value = 1.0 / float(value)

	if display_info.special_modifier == DisplayStatModifier.INVERT:
		value *= -1
	
	if typeof(value) == TYPE_FLOAT: #round to 2dp
		value = snappedf(value, 0.01)

	var stat_label := Label.new()
	stat_label.text = display_info.label + " " + str(value) + display_info.suffix
	stats.add_child(stat_label)

func _on_upgrade_button_pressed():
	if is_instance_valid(current_tower) and not Towers.get_tower_upgrades(current_tower.type).is_empty():
		UI.upgrade_tower_requested.emit(current_tower, Towers.get_tower_upgrades(current_tower.type)[0])
	
func _on_sell_button_pressed():
	UI.sell_tower_requested.emit(current_tower)
