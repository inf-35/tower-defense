extends Control
class_name Inspector

@export var tower_overview: Control #tower overview:
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
var current_unit: Unit
var _preview_upgrade_type: Towers.Type = Towers.Type.VOID ##void means no preview (normal mode)

enum InspectorMode {
	TowerOverview
}

func _ready() -> void:
	healthbar.min_value = 0.0
	stats.columns = stats_per_line

	UI.update_inspector_bar.connect(_on_inspector_contents_tower_update)
	UI.update_unit_state.connect(func(unit : Unit):
		if unit == current_unit:
			_on_inspector_contents_tower_update(current_unit)
	)
	UI.update_unit_health.connect(func(unit : Unit, max_hp : float, hp : float):
		if unit == current_unit:
			_on_inspected_tower_health_update(current_unit, max_hp, hp)
	)


func _on_inspector_contents_tower_update(unit : Unit) -> void:
	if not is_instance_valid(unit):
		_clear_inspector()
		return

	if not unit.is_ready:
		await unit.components_ready

	stats.columns = stats_per_line

	if unit != current_unit: #this is a new unit being switched to
		unit.on_event.connect(func(event: GameEvent):
			if event.event_type != GameEvent.EventType.REPLACED:
				return

			var data: UnitReplacedData = event.data as UnitReplacedData
			if data.old_unit == current_unit:
				_on_inspected_tower_replaced(current_unit, data.new_unit as Tower)
		)

	current_unit = unit
	#reset preview state when switching towers
	_preview_upgrade_type = Towers.Type.VOID

	#update header/desc normally
	_update_header_visuals(unit)
	_refresh_stats() #update stats

	unit.get_unit_state() #this prompts the unit to send us its health too

	_refresh_actions(unit) #update actions
	_update_status_display(unit)

func _clear_inspector() -> void: ##drops the currently inspected unit reference and clears transient ui state so hidden inspector transitions do not keep stale actions around
	current_unit = null
	_preview_upgrade_type = Towers.Type.VOID
	inspector_title.text = ""
	subtitle.text = ""
	description.set_parsed_text("")
	healthbar.max_value = 0.0
	healthbar.value = 0.0

	for child: Node in button_container.get_children():
		child.queue_free()
	for child: Control in stats.get_children():
		child.free()
	for child: Node in status_container.get_children():
		child.queue_free()

func _update_header_visuals(unit: Unit) -> void:
	if unit is Tower:
		var tower_type: Towers.Type = unit.type
		inspector_icon.texture = Towers.get_tower_icon(tower_type)
		inspector_title.text = Towers.get_tower_name(tower_type)
		if _preview_upgrade_type == Towers.Type.VOID:
			subtitle.text = ""
		else:
			subtitle.text = " ->%s" % Towers.get_tower_name(_preview_upgrade_type)

		description.set_parsed_text(Towers.get_tower_description(tower_type))
	else: #is enemy
		var type_key: String = ""
		type_key = Units.Type.keys()[unit.enemy_type]
		#unit keywords start with the U_ prefix
		var data = KeywordService.get_keyword_data("U_"+type_key)

		inspector_icon.texture = data.get("icon", null)
		inspector_title.text = data.get("title", "Unknown Entity")
		subtitle.text = ""
		description.set_parsed_text(data.get("description", ""))

func _refresh_stats() -> void:
	for child : Control in stats.get_children():
		child.free() #queue_free will cause bugs with get_child_count()

	if not is_instance_valid(current_unit):
		return
	#determine mode
	if _preview_upgrade_type != Towers.Type.VOID:
		_render_preview_stats()
	else:
		_render_live_stats()

func _render_live_stats() -> void: #for standard stat displays
	if current_unit is Tower:
		#use current tower instance's stat displays
		for display_info: StatDisplayInfo in current_unit.stat_displays:
			var value: Variant = get_stat_value_from_instance(current_unit, display_info)
			if value == null: continue

			value = apply_display_modifiers(value, display_info) #format
			var text: String = str(value) + display_info.suffix
			if display_info.label != "":
				text = display_info.label + " " + text

			var label := InteractiveRichTextLabel.new()
			label.bbcode_enabled = true
			label.fit_content = true
			label.set_parsed_text(text)
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			stats.add_child(label)

func _render_preview_stats() -> void:
	assert(current_unit is Tower)
	var current_type: Towers.Type = current_unit.type
	var next_type: Towers.Type = _preview_upgrade_type

	var current_proto: Tower = Towers.get_tower_prototype(current_type)
	var next_proto: Tower = Towers.get_tower_prototype(next_type)
	if (not next_proto) or (not current_proto):
		return

	current_proto.tower_position = current_unit.tower_position
	next_proto.tower_position = current_unit.tower_position

	for display_info in next_proto.stat_displays:
		#compare base stats (prototype vs prototype)
		#only modifiers included are terrain modifiers
		var val_old = get_stat_value_from_instance(current_proto, display_info)
		var val_new = get_stat_value_from_instance(next_proto, display_info)

		if val_old == null or val_new == null: continue

		#format numbers
		var old_fmt = apply_display_modifiers(val_old, display_info)
		var new_fmt = apply_display_modifiers(val_new, display_info)

		#determine color
		var color_code: String = Color.GRAY.to_html() #grey/white

		var bad_color: String = Color(0.6, 0.3, 0.3, 1.0).to_html()
		var good_color: String = Color(0.3, 0.6, 0.365, 1.0).to_html()

		#check if numeric for comparison
		if (typeof(val_new) == TYPE_FLOAT or typeof(val_new) == TYPE_INT) and \
		   (typeof(val_old) == TYPE_FLOAT or typeof(val_old) == TYPE_INT):

			var diff: float = float(val_new) - float(val_old)

			if not is_zero_approx(diff):
				#handle "lower is better" for reciprocal stats (cooldown)
				var lower_is_better: bool = (display_info.special_modifier == DisplayStatModifier.RECIPROCAL)

				if diff > 0:
					color_code = bad_color if lower_is_better else good_color #red if bad, green if good
				else:
					color_code = good_color if lower_is_better else bad_color #green if bad (lower), red if good

		#construct bbcode
		var bbcode: String = "%s [color=#888888]%s[/color] [color=%s]%s[/color]%s" % [
			display_info.label,
			str(old_fmt),
			color_code,
			str(new_fmt),
			display_info.suffix
		]

		#create richtextlabel
		var rtl := InteractiveRichTextLabel.new()
		rtl.theme_type_variation = "rt_s20_descriptive"
		rtl.bbcode_enabled = true
		rtl.set_parsed_text(bbcode)
		rtl.fit_content = true
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		stats.add_child(rtl)

	Towers.reset_tower_prototype(next_proto.type)

func _refresh_actions(unit: Unit) -> void:
	#clear existing buttons
	for child: Node in button_container.get_children():
		child.queue_free()
	#print("Clear!")
	if not unit is Tower:
		return
	var tower: Tower = unit as Tower
	#get actions from data
	var actions: Array[InspectorAction] = Towers.get_tower_actions(tower.type)
	#print("Inspector: length of actions: ", len(actions), " caused by ", Towers.Type.keys()[tower.type])
	for action: InspectorAction in actions:
		_create_action_button(tower, action)

func _create_action_button(tower: Tower, action: InspectorAction) -> void:
	if action.type == InspectorAction.ActionType.UPGRADE:
		return

	var btn: Button = action_button_scene.instantiate() as Button
	button_container.add_child(btn)

	btn.text = action.label
	btn.icon = action.icon

	var is_disabled: bool = false

	match action.type:
		InspectorAction.ActionType.UPGRADE:
			var upgrades := Towers.get_tower_upgrades(tower.type)
			if upgrades.size() <= action.upgrade_index:
				is_disabled = true #no upgrade available
			else:
				var next_type: Towers.Type = upgrades[action.upgrade_index]
				var cost := Towers.get_tower_upgrade_cost(tower.type, next_type)
				btn.text += " (%.2f)" % cost
				if Run.player.flux < cost:
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
					_update_header_visuals(tower)
					_refresh_stats()
				)
				btn.mouse_exited.connect(func():
					if not is_instance_valid(tower):
						return

					_preview_upgrade_type = Towers.Type.VOID
					_update_header_visuals(tower)
					_refresh_stats()
				)

		InspectorAction.ActionType.SELL:
			if Towers.is_tower_rite(tower.type): #TODO: un-manual this hardcoded override
				btn.text = "Excavate (%.2f)" % Run.player.RITE_EXCAVATION_COST
				if Run.player.flux < Run.player.RITE_EXCAVATION_COST or tower.current_state != Tower.State.ACTIVE:
					is_disabled = true
				btn.pressed.connect(UI.excavate_rite_requested.emit.bind(tower))
			else:
				var sell_value: float = snappedf(Towers.get_tower_refund_value(tower.type), Towers.TOWER_COST_INCREMENT)
				btn.text += " (%.2f)" % sell_value
				btn.pressed.connect(UI.sell_tower_requested.emit.bind(tower))

		InspectorAction.ActionType.CUSTOM:
			if action.custom_signal_key == &"":
				is_disabled = true
			btn.pressed.connect(func():
				if not is_instance_valid(tower):
					return
				if not is_instance_valid(tower.behavior):
					return
				if not tower.behavior.has_method(&"on_inspector_action"):
					return
				tower.behavior.on_inspector_action(action.custom_signal_key)
			)

	btn.disabled = is_disabled

func _on_inspected_tower_health_update(unit: Unit, max_hp : float, hp : float) -> void:
	healthbar.max_value = max_hp
	healthbar.value = hp

	_update_status_display(unit)

func _on_inspected_tower_replaced(_old_tower: Tower, new_tower: Tower) -> void:
	print("Inspector: replaced!")
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
	DISPLAY_ATTACK_STATUSES,
	BREACH_WAVE_PREVIEW,
}

func _update_status_display(unit: Unit) -> void:
	if not is_instance_valid(status_container):
		return

	#1. clear existing icons
	for child in status_container.get_children():
		child.queue_free()

	if not is_instance_valid(unit):
		return

	#2. check "dead" status
	#we prioritize this as the first icon if valid
	if is_instance_valid(unit.health_component):
		if unit.health_component.health <= 0:
			#you can add a "dead" entry to keywordservice or hardcode it here
			var dead_icon := preload("res://Assets/wall.png") #replace with your asset
			_create_status_widget(dead_icon, "Destroyed", "This unit is destroyed and thus disabled. Will revive next wave if not sold.", 0, true)

	#3. check modifiers/status effects
	if is_instance_valid(unit.modifiers_component):
		#we access the internal dictionary.
		#ideally modifierscomponent would expose: func get_active_statuses() -> dictionary
		var effects: Dictionary = unit.modifiers_component._status_effects

		for status_enum in effects:
			var instance = effects[status_enum]
			if instance.stack <= 0:
				continue

			#resolve data via keywordservice
			#we convert the enum (e.g. 5) to string key (e.g. "frost")
			var status_key: String = Attributes.Status.keys()[status_enum]
			var data: Dictionary = KeywordService.get_keyword_data(status_key)

			#fallback if keywordservice doesn't have data for this status yet
			var icon = data.get("icon", null)
			var title = data.get("title", status_key.capitalize())
			var desc = data.get("description", "")

			_create_status_widget(icon, title, desc, instance.stack)

func _create_status_widget(icon: Texture2D, title: String, desc: String, stacks: float, is_negative_state: bool = false) -> void:
	var wrapper = Control.new()
	wrapper.custom_minimum_size = Vector2(64, 64) #standard icon size

	var tex = TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)

	if icon:
		tex.texture = icon
	else:
		#debug fallback
		var p = PlaceholderTexture2D.new()
		p.size = Vector2(64, 64)
		tex.texture = p

	if is_negative_state:
		tex.modulate = Color(1, 0.4, 0.4) #red tint for death

	wrapper.add_child(tex)

	#stack count label
	if stacks > 1:
		var lbl = Label.new()
		lbl.text = str(int(stacks))
		#position at bottom-right
		lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		lbl.position -= Vector2(8, 0) #small offset
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
				#critical: do not call queue_free() directly
				#call on_link_mouse_exited(), which triggers the "grace period" logic
				#allowing the player to move their mouse from the icon into the tooltip
				#to read nested keywords
				tooltip_instance.on_link_mouse_exited()

			wrapper.remove_meta(&"active_tooltip")
	)

	status_container.add_child(wrapper)

static func get_stat_value_from_instance(tower: Tower, info: StatDisplayInfo) -> Variant:
	var value: Variant = null
	#handle overrides
	match info.special_modifier:
		DisplayStatModifier.CORE_FLUX: return Run.player.flux
		DisplayStatModifier.CAPACITY: return Towers.get_tower_capacity(tower.type)
		DisplayStatModifier.LINE_BREAK: return null
		DisplayStatModifier.CAPACITY_GENERATION:
			#return tower.get_intrinsic_effect_attribute(Effects.Type.CAPACITY_GENERATOR, &"last_capacity_generation")
			return null
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
		DisplayStatModifier.BREACH_WAVE_PREVIEW:
			return tower.get_behavior_attribute(ID.UnitState.BREACH_WAVE_PREVIEW)
		DisplayStatModifier.DISPLAY_ATTACK_STATUSES:
			if not is_instance_valid(tower.attack_component):
				return null

			#access the data defining the attack
			var data: AttackData = tower.attack_component.attack_data
			return _format_status_effects(data)


	#if we're still here, we didnt hit any overrides
	if tower.modifiers_component:
		if tower.modifiers_component.has_stat(info.attribute):
			value = tower.modifiers_component.pull_stat(info.attribute)
		if info.dynamic_attribute != &"" and tower.modifiers_component.has_dynamic_stat(info.dynamic_attribute):
			value = tower.modifiers_component.pull_dynamic_stat(info.dynamic_attribute)
	else:
		value =  tower.get_stat(info.attribute)
	#elif Towers.get_tower_stat(tower.type, info.attribute):
		#value = Towers.get_tower_stat(tower.type, info.attribute)
	if not value: value = 0.0

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
		return "None" #or null to hide the line entirely

	var parts: Array[String] = []

	for status_effect: StatusEffectPrototype in attack_data.status_effects:
		var stacks: float = status_effect.stack
		var duration: float = status_effect.cooldown

		#get string key (e.g. 5 -> "poison")
		var status_key: String = Attributes.Status.keys()[status_effect.type]

		#use keywordservice to get the icon + colored name
		var bbcode_name: String = KeywordService.parse_text_for_bbcode("{%s}" % status_key)

		#format: "[icon] poison (5s)" or "[icon] frost x2 (3s)"
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
