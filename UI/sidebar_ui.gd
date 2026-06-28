extends Control
class_name SidebarUI

@export var towers_bar: VBoxContainer
@export var start_wave_button: Button
@export var trade_button: Button
@export var trade_button_label: InteractiveRichTextLabel

const START_WAVE_BUTTON_TEXT: String = "Start Wave (Space)"

var tower_option_prototype: PackedScene = preload("res://UI/tower_option.tscn")
var _tutorial_start_wave_locked: bool = false
var _trade_button_has_unseen_stock: bool = false
var _trade_button_wiggle_tween: Tween

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
		start_wave_button.text = START_WAVE_BUTTON_TEXT
		_update_start_wave_button_state()
	)
	UI.hide_building_ui.connect(func():
		start_wave_button.text = "Wave in Progress" #more descriptive
		start_wave_button.disabled = true
	)

	start_wave_button.pressed.connect(_emit_start_wave)
	UI.tutorial_manager.start_wave_lock_changed.connect(func(locked: bool):
		_tutorial_start_wave_locked = locked
		_update_start_wave_button_state()
	)

	trade_button.pressed.connect(func():
		Run.player.trader_service.open_menu()
	)
	UI.trader_unseen_stock_changed.connect(_update_trade_button_notification)
	trade_button.resized.connect(_update_trade_button_pivot)

	#request initial state if player might have initialized before ui connected
	#(though with autoload order or call_deferred this might not be strictly necessary,
	#but good for robustness if player's _ready completes and emits before ui's _ready connects)
	if Run.has_active_run() and is_instance_valid(Run.player):
		_on_player_tower_types_update(Run.player.unlocked_towers, Run.player.rite_inventory)
	else:
		_clear_towers_bar() #ensure it's empty if no towerss initially

	UI.tutorial_manager.register_element(TutorialStep.Reference.START_WAVE_BUTTON, start_wave_button)
	_update_trade_button_pivot()
	if Run.has_active_run() and is_instance_valid(Run.player):
		_update_trade_button_notification(Run.player.trader_service.has_unseen_stock())
	else:
		_update_trade_button_notification(false)

func _input(event: InputEvent) -> void: ##allows starting the build phase from the keyboard without relying on button focus
	if not event.is_action_pressed("start_wave"):
		return
	if not _can_start_wave():
		return
	get_viewport().set_input_as_handled()
	_emit_start_wave()


func _update_start_wave_button_state() -> void: ##only the build-phase label should become interactable
	if start_wave_button.text != START_WAVE_BUTTON_TEXT:
		return
	start_wave_button.disabled = _tutorial_start_wave_locked


func _can_start_wave() -> bool: ##matches the button's live availability so keyboard and mouse behave the same way
	return start_wave_button.text == START_WAVE_BUTTON_TEXT and not start_wave_button.disabled


func _emit_start_wave() -> void: ##shares the same start-wave action between button clicks and the space-bar shortcut
	if not _can_start_wave():
		return
	UI.building_phase_ended.emit()


func _update_trade_button_pivot() -> void: ##keeps the wiggle centered on the button rather than the top-left corner
	trade_button.pivot_offset = trade_button.size * 0.5

func _update_trade_button_notification(has_unseen_stock: bool) -> void: ##toggles the blue unseen-restock badge on the trade button
	var label_text: String = "Trade (T)"
	if has_unseen_stock:
		label_text += "\n" + KeywordService.wrap_text("[restocked!]", "action")
	trade_button_label.set_parsed_text(label_text)
	if has_unseen_stock != _trade_button_has_unseen_stock:
		_set_trade_button_wiggle_active(has_unseen_stock)
	_trade_button_has_unseen_stock = has_unseen_stock


func _set_trade_button_wiggle_active(is_active: bool) -> void: ##starts or stops the unseen-stock wiggle to match the badge state
	if is_instance_valid(_trade_button_wiggle_tween):
		_trade_button_wiggle_tween.kill()
	trade_button.rotation = 0.0
	if not is_active:
		return
	_trade_button_wiggle_tween = create_tween()
	_trade_button_wiggle_tween.set_loops()
	_trade_button_wiggle_tween.tween_property(trade_button, "rotation", deg_to_rad(-1.2), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_trade_button_wiggle_tween.tween_property(trade_button, "rotation", deg_to_rad(1.2), 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_trade_button_wiggle_tween.tween_property(trade_button, "rotation", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_trade_button_wiggle_tween.tween_interval(0.55)


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
	UI.tower_option_selected.emit(type_id)
	UI.tower_selected.emit(Towers.get_tower_prototype(type_id)) #update click handler
	UI.update_inspector_bar.emit(Towers.get_tower_prototype(type_id)) #update inspector bar to fit whatever we're selecting
