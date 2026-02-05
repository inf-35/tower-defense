class_name TradePanel
extends RewardPanel

@export var wave_text: InteractiveRichTextLabel
@export var exit_button: Button

func _ready() -> void:
	visible = false
	
	UI.trader_open.connect(func(): visible = true)
	UI.trader_close.connect(func(): visible = false)
	UI.trader_update_stock.connect(_present_options)
	UI.trader_update_restock_cost.connect(_update_restock_cost)
	UI.trader_update_waves_to_next_restock.connect(_update_restock_waves)
	UI.update_flux.connect(func(_flux): _update_restock_cost(Player.trader_service.get_restock_cost()))
	reroll_button.pressed.connect(func():
		UI.trader_force_restock_requested.emit()
	)
	exit_button.pressed.connect(func():
		Player.trader_service.close_menu()
	)
	
func _present_options(choices: Array[Reward]) -> void:
	_clear_options()
	
	for i: int in choices.size():
		var reward_data: Reward = choices[i]
		_instantiate_card(reward_data, i)
	
func _update_restock_cost(restock_cost: float) -> void:
	reroll_button.text = "Restock (%.2f)" % restock_cost

func _update_restock_waves(waves: int) -> void:
	wave_text.text = "Restocks automatically in %d waves." % waves

func _instantiate_card(data: Reward, index: int) -> void:
	if not card_scene:
		push_error("RewardUI: No card_scene assigned!")
		return
		
	if not data:
		var blocker := ShopOptionCard.new()
		blocker.custom_minimum_size = Vector2(1200, 300)
		blocker.self_modulate = Color.TRANSPARENT
		card_list.add_child(blocker)
		active_cards.append(blocker)
		return
		
	var card_instance = card_scene.instantiate() as RewardOptionCard
	if not card_instance:
		push_error("RewardUI: Assigned scene is not a RewardOptionCard.")
		return
		
	card_list.add_child(card_instance)
	active_cards.append(card_instance)
	
	# 1. Setup Data and Animation
	card_instance.setup(data, index)
	
	# 2. Connect Signals
	# We bind the index (choice_id) so the UI bus knows which reward was picked
	card_instance.selected.connect(func():
		UI.trader_choice_selected.emit(index)
	)
