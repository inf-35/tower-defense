extends Control
class_name SidebarUI

@export var towers_bar: VBoxContainer
@export var trade_button: Button
@export var trade_button_label: InteractiveRichTextLabel

var tower_option_prototype: PackedScene = preload("res://UI/tower_option.tscn")
var _trade_button_has_unseen_stock: bool = false
var _trade_button_wiggle_tween: Tween
var _tower_options_by_type: Dictionary[Towers.Type, TowerOption] = {}
var _selected_tower_type: Towers.Type = Towers.Type.VOID

func _ready() -> void:
	#initial population and updates are handled by connecting to the signal.
	#player.towerss setter will emit the initial list.
	
	if not Run.is_run_ready():
		await Run.references_ready

	UI.update_tower_types.connect(_on_player_tower_types_update)
	UI.tower_option_selected.connect(_on_tower_option_selected)
	UI.update_tower_counts.connect(func():
		_on_player_tower_types_update(Run.player.unlocked_towers, Run.player.rite_inventory)
	)
	ClickHandler.tower_was_deselected.connect(_clear_selected_tower_option)

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

	_update_trade_button_pivot()
	if Run.has_active_run() and is_instance_valid(Run.player):
		_update_trade_button_notification(Run.player.trader_service.has_unseen_stock())
	else:
		_update_trade_button_notification(false)

	var tower_sidebar: Control = towers_bar.get_parent().get_parent().get_parent() as Control
	UI.tutorial_manager.register_element(TutorialContent.Element.TOWER_BAR, tower_sidebar if is_instance_valid(tower_sidebar) else self)
	UI.tutorial_manager.register_element(TutorialContent.Element.TRADE_BUTTON, trade_button)

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
	_tower_options_by_type.clear()
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
		_tower_options_by_type[unlocked_tower_type] = tower_option

		_sync_selected_tower_option()

func _on_tower_button_pressed(type_id: Towers.Type) -> void:
	UI.tower_option_selected.emit(type_id)
	UI.tower_selected.emit(Towers.get_tower_prototype(type_id)) #update click handler
	UI.update_inspector_bar.emit(Towers.get_tower_prototype(type_id)) #update inspector bar to fit whatever we're selecting

func _on_tower_option_selected(tower_type: Towers.Type) -> void: ##keeps one sidebar card highlighted while its build preview is the active interaction mode
	_selected_tower_type = tower_type
	_sync_selected_tower_option()

func _clear_selected_tower_option() -> void: ##clears the persistent card highlight when the click handler exits preview/selection flow
	_selected_tower_type = Towers.Type.VOID
	_sync_selected_tower_option()

func _sync_selected_tower_option() -> void: ##re-applies card selection after rebuilds so counts and unlock refreshes do not drop the current highlight
	for tower_type: Towers.Type in _tower_options_by_type:
		_tower_options_by_type[tower_type].set_selected(tower_type == _selected_tower_type)
