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
var _preview_upgrade_type: Towers.Type = Towers.Type.VOID ## void means no preview (normal mode)

enum InspectorMode {
	TowerOverview
}

func _ready():
	healthbar.min_value = 0.0
	stats.columns = stats_per_line

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
	if not tower.is_ready:
		await tower.components_ready
	
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
	# update header/desc normally
	_update_header_visuals(tower.type)
	# reset preview state when switching towers
	_preview_upgrade_type = Towers.Type.VOID

	
	_refresh_stats() # update stats
	
	tower.get_unit_state() #this prompts the tower to send us its health too
	
	_refresh_actions(tower) # update actions
	_update_status_display(tower)
	
func _update_header_visuals(tower_type: Towers.Type) -> void:
	inspector_icon.texture = Towers.get_tower_icon(tower_type)
	inspector_title.text = Towers.get_tower_name(tower_type)
	if _preview_upgrade_type == Towers.Type.VOID:
		subtitle.text = ""
	else:
		subtitle.text = " ->%s" % Towers.get_tower_name(_preview_upgrade_type)
		
	description.set_parsed_text(Towers.get_tower_description(tower_type))
	
func _refresh_stats() -> void:
	for child : Control in stats.get_children():
		child.free() #queue_free will cause bugs with get_child_count()
		
	if not is_instance_valid(current_tower):
		return
	# determine mode
	if _preview_upgrade_type != Towers.Type.VOID:
		_render_preview_stats()
	else:
		_render_live_stats()
		
func _render_live_stats() -> void: # for standard stat displays
	# use current tower instance's stat displays
	for display_info: StatDisplayInfo in current_tower.stat_displays:
		var value: Variant = get_stat_value_from_instance(current_tower, display_info)
		if value == null: continue
		
		value = apply_display_modifiers(value, display_info) #format
		var text: String = display_info.label + " " + str(value) + display_info.suffix
		
		var label := InteractiveRichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.set_parsed_text(text)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		stats.add_child(label)

func _render_preview_stats() -> void:
	var current_type: Towers.Type = current_tower.type
	var next_type: Towers.Type = _preview_upgrade_type
	
	var current_proto: Tower = Towers.get_tower_prototype(current_type)
	var next_proto: Tower = Towers.get_tower_prototype(next_type)
	if (not next_proto) or (not current_proto):
		return
	
	current_proto.tower_position = current_tower.tower_position
	next_proto.tower_position = current_tower.tower_position 
	
	for display_info in next_proto.stat_displays:
		# compare BASE stats (prototype vs prototype)
		# only modifiers included are terrain modifiers
		var val_old = get_stat_value_from_instance(current_proto, display_info)
		var val_new = get_stat_value_from_instance(next_proto, display_info)

		if val_old == null or val_new == null: continue
		
		# Format Numbers
		var old_fmt = apply_display_modifiers(val_old, display_info)
		var new_fmt = apply_display_modifiers(val_new, display_info)
		
		# Determine Color
		var color_code: String = Color.GRAY.to_html() # Grey/White
		
		var bad_color: String = Color(0.6, 0.3, 0.3, 1.0).to_html()
		var good_color: String = Color(0.3, 0.6, 0.365, 1.0).to_html()
	
		# Check if numeric for comparison
		if (typeof(val_new) == TYPE_FLOAT or typeof(val_new) == TYPE_INT) and \
		   (typeof(val_old) == TYPE_FLOAT or typeof(val_old) == TYPE_INT):
			
			var diff: float = float(val_new) - float(val_old)
			
			if not is_zero_approx(diff):
				# Handle "Lower is Better" for Reciprocal stats (Cooldown)
				var lower_is_better: bool = (display_info.special_modifier == DisplayStatModifier.RECIPROCAL)
				
				if diff > 0:
					color_code = bad_color if lower_is_better else good_color # Red if bad, Green if good
				else:
					color_code = good_color if lower_is_better else bad_color # Green if bad (lower), Red if good
		
		# Construct BBCode
		var bbcode: String = "%s [color=#888888]%s[/color] [color=%s]%s[/color]%s" % [
			display_info.label, 
			str(old_fmt), 
			color_code, 
			str(new_fmt),
			display_info.suffix
		]
		
		# Create RichTextLabel
		var rtl := InteractiveRichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.set_parsed_text(bbcode)
		rtl.fit_content = true
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		stats.add_child(rtl)
		
	Towers.reset_tower_prototype(next_proto.type)

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
					
				btn.pressed.connect(func():
					if not is_instance_valid(tower):
						return
					
					_preview_upgrade_type = Towers.Type.VOID
					UI.upgrade_tower_requested.emit(tower, next_type)
				)
				btn.mouse_entered.connect(func():
					if not is_instance_valid(tower):
						return
						
					_preview_upgrade_type = next_type
					_update_header_visuals(tower.type)
					_refresh_stats()
				)
				btn.mouse_exited.connect(func():
					if not is_instance_valid(tower):
						return

					_preview_upgrade_type = Towers.Type.VOID
					_update_header_visuals(tower.type)
					_refresh_stats()
				)
				
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
	DISPLAY_ATTACK_STATUSES
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

static func get_stat_value_from_instance(tower: Tower, info: StatDisplayInfo) -> Variant:
	var value: Variant = null
	# handle overrides
	match info.special_modifier:
		DisplayStatModifier.CORE_FLUX: return Player.flux
		DisplayStatModifier.CAPACITY: return Towers.get_tower_capacity(tower.type)
		DisplayStatModifier.LINE_BREAK: return null
		DisplayStatModifier.CAPACITY_GENERATION: 
			return tower.get_intrinsic_effect_attribute(Effects.Type.CAPACITY_GENERATOR, &"last_capacity_generation")
		DisplayStatModifier.WAVES_LEFT_IN_PHASE:
			return tower.get_behavior_attribute(ID.UnitState.WAVES_LEFT_IN_PHASE)
		DisplayStatModifier.ANOMALY_REWARD_PREVIEW:
			var waves_left_to_reward: int = tower.get_behavior_attribute(ID.UnitState.WAVES_LEFT_IN_PHASE)
			var reward: Reward = tower.get_behavior_attribute(ID.UnitState.REWARD_PREVIEW)
			
			if reward.type == Reward.Type.ADD_RELIC:
				value = reward.relic.title + " in " + str(waves_left_to_reward) + " waves."
			elif reward.type == Reward.Type.UNLOCK_TOWER:
				value = Towers.get_tower_name(reward.tower_type) + " in " + str(waves_left_to_reward) + " waves."
			elif reward.type == Reward.Type.ADD_RITE:
				value = Towers.get_tower_name(reward.rite_type) + " in " + str(waves_left_to_reward) + " waves."
			
			return value
		DisplayStatModifier.DISPLAY_ATTACK_STATUSES:
			if not is_instance_valid(tower.attack_component):
				return null
			
			# Access the data defining the attack
			var data: AttackData = tower.attack_component.attack_data
			return _format_status_effects(data)
			
	# if we're still here, we didnt hit any overrides
	if tower.modifiers_component and tower.modifiers_component.has_stat(info.attribute):
		value = tower.modifiers_component.pull_stat(info.attribute)
	else:
		value =  tower.get_stat(info.attribute)
	#elif Towers.get_tower_stat(tower.type, info.attribute):
		#value = Towers.get_tower_stat(tower.type, info.attribute)
		
	return value
	
static func get_stat_value_from_unit(unit: Unit, info: StatDisplayInfo) -> Variant:
	var value: Variant
	
	if unit.modifiers_component and unit.modifiers_component.has_stat(info.attribute):
		value = unit.modifiers_component.pull_stat(info.attribute)
	else:
		value =  unit.get_stat(info.attribute)
	
	return value
	
static func _format_status_effects(attack_data: AttackData) -> String:
	if not attack_data or attack_data.status_effects.is_empty():
		return "None" # Or null to hide the line entirely
		
	var parts: Array[String] = []

	for status_effect: StatusEffectPrototype in attack_data.status_effects:
		var stacks: float = status_effect.stack
		var duration: float = status_effect.cooldown
		
		# Get String Key (e.g. 5 -> "POISON")
		var status_key: String = Attributes.Status.keys()[status_effect.type]
		
		# Use KeywordService to get the Icon + Colored Name
		var bbcode_name: String = KeywordService.parse_text_for_bbcode("{%s}" % status_key)
		
		# Format: "[Icon] Poison (5s)" or "[Icon] Frost x2 (3s)"
		var entry = bbcode_name
		if stacks > 0.0:
			entry += " x%d" % snappedf(stacks, 0.1)
		if duration > 0:
			entry += " [color=#888888](%ss)[/color]" % str(snappedf(duration, 0.1))
		else:
			entry += " (permanent)"
			
		parts.append(entry)
		
	return ", ".join(parts)
	
static func apply_display_modifiers(value: Variant, info: StatDisplayInfo) -> Variant: ##for formatting raw values (from _get_stat_value_from_instance)
	if info.special_modifier == DisplayStatModifier.RECIPROCAL and float(value) != 0:
		value = 1.0 / float(value)
	if info.special_modifier == DisplayStatModifier.INVERT:
		value *= -1

	if typeof(value) == TYPE_FLOAT:
		return snappedf(value, 0.01)
	return value
