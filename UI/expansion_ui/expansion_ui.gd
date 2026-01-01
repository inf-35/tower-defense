extends Panel

@export var _vbox: VBoxContainer

# --- configuration ---
@export_group("Info Display Settings")
@export var show_tile_count: bool = false
@export var show_special_terrain: bool = false
@export var show_features: bool = true
@export var show_anomaly_contents: bool = true ## if true, tries to read the reward inside the anomaly

var option_buttons: Array[Button]
var _pending_choice_id: int
var _confirmation_button: Button

func _ready():
	visible = false
	UI.display_expansion_choices.connect(func(expansion_choices: Array[ExpansionChoice]):
		_present_options(expansion_choices)
	)
	UI.hide_expansion_choices.connect(_hide_options)
	UI.display_expansion_confirmation.connect(_present_confirmation)
	UI.hide_expansion_confirmation.connect(_hide_confirmation)
	
func _present_options(data: Array[ExpansionChoice]):
	_populate_buttons(data)
	visible = true
	
func _hide_options():
	visible = false
	
func _present_confirmation(pending_choice_id: int):
	if not is_instance_valid(_confirmation_button):
		return
		
	self._pending_choice_id = pending_choice_id
	_confirmation_button.modulate = Color.WHITE
	_confirmation_button.disabled = false

func _hide_confirmation():
	if not is_instance_valid(_confirmation_button):
		return
	_confirmation_button.modulate = Color.TRANSPARENT
	_confirmation_button.disabled = true
	
func _populate_buttons(data: Array[ExpansionChoice]):
	for button: Node in option_buttons:
		button.queue_free()
	option_buttons.clear()
	
	for i: int in len(data):
		var choice: ExpansionChoice = data[i]
		
		var btn: ExpansionOptionButton = preload("res://UI/expansion_ui/expansion_option_button.tscn").instantiate()
		# generate dynamic text based on the choice data
		btn.set_parsed_text(_generate_button_text(i, choice))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT 
		
		btn.name = "Btn_selection_%s" % str(i)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		btn.mouse_entered.connect(_on_choice_hovered.bind(i))
		btn.mouse_exited.connect(_on_choice_unhovered.bind(i))
		
		_vbox.add_child(btn)
		option_buttons.append(btn)
		
	_confirmation_button = Button.new()
	_confirmation_button.text = "Apply expansion."
	_confirmation_button.pressed.connect(_on_confirmation_pressed)
	_confirmation_button.modulate = Color.TRANSPARENT 
	_confirmation_button.disabled = true
	_vbox.add_child(_confirmation_button)

func _generate_button_text(index: int, choice: ExpansionChoice) -> String:
	var text: String = "Option %d" % (index + 1)
	
	if choice.block_data.is_empty():
		return text + " (Empty)"
		
	# tile count
	if show_tile_count:
		text += " %d Tiles" % choice.block_data.size()
		
	var terrain_counts: Dictionary[String, int] = {}
	var standard_feature_counts: Dictionary[String, int] = {}
	var distinct_anomaly_list: Array[String] = []
	
	for cell: Vector2i in choice.block_data:
		var cell_data: Terrain.CellData = choice.block_data[cell]
		
		# terrain analysis
		if show_special_terrain and cell_data.terrain != Terrain.Base.EARTH:
			var t_name = Terrain.Base.keys()[cell_data.terrain].capitalize()
			terrain_counts[t_name] = terrain_counts.get(t_name, 0) + 1
			
		# feature analysis
		if show_features and cell_data.feature != Towers.Type.VOID:
			var feature_name = Towers.Type.keys()[cell_data.feature].capitalize()
			
			if cell_data.feature == Towers.Type.ANOMALY:
				# anomalies are always distinct
				var anomaly_desc: String = feature_name
				if show_anomaly_contents and cell_data.initial_state.has(&"_anomaly_data"):
					var anomaly_data: AnomalyData = cell_data.initial_state[&"_anomaly_data"]
					if anomaly_data.reward != null:
						if anomaly_data.reward.type == Reward.Type.UNLOCK_TOWER:
							var tower_type: Towers.Type = anomaly_data.reward.tower_type
							anomaly_desc += " ({T_%s})" % Towers.Type.keys()[tower_type]
						elif anomaly_data.reward.type == Reward.Type.ADD_RELIC:
							var relic: RelicData = anomaly_data.reward.relic
							anomaly_desc += " ({R_%s})" % str(relic.type)
							print(relic.title.to_snake_case().to_upper(), " by expansion")
						elif anomaly_data.reward.type == Reward.Type.ADD_RITE:
							var rite_type: Towers.Type = anomaly_data.reward.rite_type
							anomaly_desc += " ({T_%s})" % Towers.Type.keys()[rite_type]
						else:
							anomaly_desc += " (%s)" % anomaly_data.reward.title
				distinct_anomaly_list.append(anomaly_desc)
			else:
				# all other towers are consolidated
				standard_feature_counts[feature_name] = standard_feature_counts.get(feature_name, 0) + 1

	# append terrain
	if not terrain_counts.is_empty():
		text += ""
		for t_name in terrain_counts:
			text += " %d %s" % [terrain_counts[t_name], t_name]
			
	# append features
	if not standard_feature_counts.is_empty() or not distinct_anomaly_list.is_empty():
		text += ""

		for f_name in standard_feature_counts:
			text += " %d %s" % [standard_feature_counts[f_name], f_name]

		for anomaly_desc in distinct_anomaly_list:
			text += " %s" % anomaly_desc
			
	return text

func _on_choice_pressed(choice_id: int):
	UI.choice_focused.emit(choice_id)

func _on_choice_hovered(choice_id: int):
	UI.choice_hovered.emit(choice_id)
	
func _on_choice_unhovered(choice_id: int):
	UI.choice_unhovered.emit(choice_id)

func _on_confirmation_pressed():
	UI.choice_selected.emit(_pending_choice_id)
