extends Control
class_name SidebarUI

@export var towers_bar: VBoxContainer
@export var start_wave_button: Button
@export var trade_button: Button
@export var trade_button_label: InteractiveRichTextLabel

var tower_option_prototype: PackedScene = preload("res://UI/tower_option.tscn")
var _tutorial_start_wave_locked: bool = false

func _ready() -> void:
	#initial population and updates are handled by connecting to the signal.
	#player.towerss setter will emit the initial list.
	
	if not Run.is_run_ready():
		await Run.references_ready

	UI.update_tower_types.connect(_on_player_tower_types_update)
	UI.update_tower_counts.connect(func():
		_on_player_tower_types_update(Run.player.unlocked_towers, Run.player.rite_inventory)
	)

	UI.show_building_ui.connect(func():
		start_wave_button.text = "Start Wave" #more descriptive
		_update_start_wave_button_state()
	)
	UI.hide_building_ui.connect(func():
		start_wave_button.text = "Wave in Progress" #more descriptive
		start_wave_button.disabled = true
	)

	start_wave_button.pressed.connect(func():
		UI.building_phase_ended.emit()
	)
	UI.tutorial_manager.start_wave_lock_changed.connect(func(locked: bool):
		_tutorial_start_wave_locked = locked
		_update_start_wave_button_state()
	)

	trade_button.pressed.connect(func():
		Run.player.trader_service.open_menu()
	)
	UI.trader_unseen_stock_changed.connect(_update_trade_button_notification)

	#request initial state if player might have initialized before ui connected
	#(though with autoload order or call_deferred this might not be strictly necessary,
	#but good for robustness if player's _ready completes and emits before ui's _ready connects)
	if Run.has_active_run() and is_instance_valid(Run.player):
		_on_player_tower_types_update(Run.player.unlocked_towers, Run.player.rite_inventory)
	else:
		_clear_towers_bar() #ensure it's empty if no towerss initially

	UI.tutorial_manager.register_element(TutorialStep.Reference.START_WAVE_BUTTON, start_wave_button)
	if Run.has_active_run() and is_instance_valid(Run.player):
		_update_trade_button_notification(Run.player.trader_service.has_unseen_stock())
	else:
		_update_trade_button_notification(false)

func _update_start_wave_button_state() -> void:
	if start_wave_button.text != "Start Wave":
		return
	start_wave_button.disabled = _tutorial_start_wave_locked

func _update_trade_button_notification(has_unseen_stock: bool) -> void: ##toggles the blue unseen-restock badge on the trade button
	var label_text: String = "Trade (T)"
	if has_unseen_stock:
		label_text += "\n" + KeywordService.wrap_text("[restocked!]", "action")
	trade_button_label.set_parsed_text(label_text)


func _clear_towers_bar() -> void:
	for child in towers_bar.get_children():
		towers_bar.remove_child(child) #correct way to remove
		child.queue_free() #then free it

func _on_player_tower_types_update(unlocked_tower_types : Dictionary[Towers.Type, bool], _rite_inventory: Dictionary[Towers.Type, int]) -> void:
	_clear_towers_bar()

	var tower_types_by_id: Array[Towers.Type] = unlocked_tower_types.keys()
	tower_types_by_id.sort()

	for unlocked_tower_type : Towers.Type in tower_types_by_id:
		if not unlocked_tower_types[unlocked_tower_type]:
			continue

		var tower_option: TowerOption = tower_option_prototype.instantiate()
		tower_option.name = "TowerOption_" + str(Towers.Type.keys()[unlocked_tower_type])
		tower_option.display_tower_type(unlocked_tower_type)

		tower_option.pressed.connect(_on_tower_button_pressed.bind(unlocked_tower_type))
		towers_bar.add_child(tower_option)

		if unlocked_tower_type == Towers.Type.PALISADE:
			UI.tutorial_manager.register_element(TutorialStep.Reference.PALISADE_BUTTON, tower_option)
		elif unlocked_tower_type == Towers.Type.TURRET:
			UI.tutorial_manager.register_element(TutorialStep.Reference.TURRET_BUTTON, tower_option)

func _on_tower_button_pressed(type_id: Towers.Type) -> void:
	UI.tower_selected.emit(Towers.get_tower_prototype(type_id)) #update click handler
	UI.update_inspector_bar.emit(Towers.get_tower_prototype(type_id)) #update inspector bar to fit whatever we're selecting
