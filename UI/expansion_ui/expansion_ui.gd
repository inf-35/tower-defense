extends Panel

@export var _vbox: VBoxContainer

const OPTION_ENTRANCE_OFFSET: Vector2 = Vector2(0, -48)
const OPTION_ENTRANCE_DURATION: float = 0.48
const OPTION_ENTRANCE_STAGGER: float = 0.08

#--- configuration ---
@export_group("Info Display Settings")
@export var show_tile_count: bool = false
@export var show_special_terrain: bool = false
@export var show_features: bool = true
@export var show_anomaly_contents: bool = true ##if true, tries to read the reward inside the anomaly

var option_buttons: Array[Button]
var _pending_choice_id: int
var _confirmation_button: Button
var _finish_button: Button

func _ready() -> void:
	visible = false
	UI.display_expansion_choices.connect(func(expansion_choices: Array[ExpansionChoice]):
		_present_options(expansion_choices)
	)
	UI.hide_expansion_choices.connect(_hide_options)
	UI.display_expansion_confirmation.connect(_present_confirmation)
	UI.hide_expansion_confirmation.connect(_hide_confirmation)
	UI.display_expansion_exit.connect(_present_exit)
	UI.hide_expansion_exit.connect(_hide_exit)

func _present_options(data: Array[ExpansionChoice]) -> void:
	_populate_buttons(data)
	visible = true

func _hide_options() -> void:
	visible = false

func _present_confirmation(pending_choice_id: int) -> void:
	if not is_instance_valid(_confirmation_button):
		return

	self._pending_choice_id = pending_choice_id
	_confirmation_button.disabled = false

func _hide_confirmation() -> void:
	if not is_instance_valid(_confirmation_button):
		return
	_confirmation_button.disabled = true

func _present_exit() -> void:
	_finish_button.disabled = false
	_confirmation_button.text = "Apply expansion (more enemies will spawn)"

func _hide_exit() -> void:
	_finish_button.disabled = true
	_confirmation_button.text = "Apply expansion"


func _populate_buttons(data: Array[ExpansionChoice]) -> void:
	for button: Node in _vbox.get_children():
		button.queue_free()

	option_buttons.clear()

	for i: int in len(data):
		var choice: ExpansionChoice = data[i]

		var btn: ExpansionOptionButton = preload("res://UI/expansion_ui/expansion_option_button.tscn").instantiate()
		#generate dynamic text based on the choice data
		btn.set_parsed_text(_generate_button_text(i, choice))
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER

		btn.name = "Btn_selection_%s" % str(i)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		btn.mouse_entered.connect(_on_choice_hovered.bind(i))
		btn.mouse_exited.connect(_on_choice_unhovered.bind(i))

		_add_animated_button(btn, float(i) * OPTION_ENTRANCE_STAGGER)
		option_buttons.append(btn)

	_confirmation_button = Button.new()
	_confirmation_button.use_parent_material = true
	_confirmation_button.text = "Apply expansion."
	_confirmation_button.pressed.connect(_on_confirmation_pressed)
	_confirmation_button.disabled = true
	_add_animated_button(_confirmation_button, float(data.size()) * OPTION_ENTRANCE_STAGGER)

	_finish_button = Button.new()
	_finish_button.use_parent_material = true
	_finish_button.text = "Finish expansions (exit)."
	_finish_button.pressed.connect(_on_finish_pressed)
	_finish_button.disabled = true
	_vbox.add_child(_finish_button)

func _add_animated_button(button: Control, delay: float) -> void: ##wraps a dynamic expansion button and starts its staggered entrance
	var animation: AnimatableUI = AnimatableUI.new()
	animation.content = button
	animation.custom_minimum_size = button.custom_minimum_size
	animation.use_parent_material = true
	animation.slide_offset = OPTION_ENTRANCE_OFFSET
	animation.entrance_duration = OPTION_ENTRANCE_DURATION
	animation.entrance_delay = delay
	animation.hover_enabled = false
	animation.add_child(button)
	_vbox.add_child(animation)
	animation.custom_minimum_size = button.get_combined_minimum_size()
	animation.animate_entrance()

func _generate_button_text(_index: int, choice: ExpansionChoice) -> String:
	if choice.block_data.is_empty():
		return "Empty"

	var settlement_count: int = 0
	var ruin_count: int = 0
	var feature_counts: Dictionary[Towers.Type, int] = {}

	for cell_data: Terrain.CellData in choice.block_data.values():
		if cell_data.terrain == Terrain.Base.SETTLEMENT:
			settlement_count += 1

		if cell_data.feature == Towers.Type.VOID:
			continue

		if cell_data.feature == Towers.Type.RUINS:
			ruin_count += 1
			continue

		if not _should_show_feature_type(cell_data.feature):
			continue

		feature_counts[cell_data.feature] = feature_counts.get(cell_data.feature, 0) + 1

	var segments: Array[String] = []
	if ruin_count > 0:
		segments.append("%d {T_RUINS}" % ruin_count)
	if settlement_count > 0:
		segments.append("%d {SETTLEMENT}" % settlement_count)

	var sorted_feature_types: Array[int] = []
	sorted_feature_types.assign(feature_counts.keys())
	sorted_feature_types.sort()
	for feature_type: Towers.Type in sorted_feature_types:
		segments.append("%d {T_%s}" % [feature_counts[feature_type], Towers.Type.keys()[feature_type]])

	if segments.is_empty():
		return "Empty"
	return "    ".join(segments)

func _should_show_feature_type(feature_type: Towers.Type) -> bool: ##filters expansion option listings down to player-meaningful non-environmental structures while leaving ruins and settlement terrain handled separately
	if Towers.is_tower_environmental(feature_type):
		return false

	var prototype: Tower = Towers.get_tower_prototype(feature_type)
	if not is_instance_valid(prototype):
		return false

	return not prototype.hostile

func _count_land_tiles(choice: ExpansionChoice) -> int:
	var count: int = 0
	for cell: Vector2i in choice.block_data:
		if not Terrain.is_waterlike(choice.block_data[cell].terrain):
			count += 1
	return count

func _on_choice_pressed(choice_id: int) -> void:
	UI.choice_focused.emit(choice_id)

func _on_choice_hovered(choice_id: int) -> void:
	UI.choice_hovered.emit(choice_id)

func _on_choice_unhovered(choice_id: int) -> void:
	UI.choice_unhovered.emit(choice_id)

func _on_confirmation_pressed() -> void:
	UI.choice_selected.emit(_pending_choice_id)

func _on_finish_pressed() -> void:
	UI.expansion_finished.emit()
