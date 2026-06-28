extends Node
class_name TraderService

signal item_purchased(reward: Reward, slot_index: int)
signal stock_restocked(is_manual: bool)

#--- configuration ---
const SLOT_COUNT: int = 3
const AUTO_RESTOCK_INTERVAL: int = 2 ##waves between free restocks

#--- state (persistent) ---
#each slot contains either a reward resource or null (exhausted)
var _current_stock: Array[Reward] = []
var _manual_restocks: int = 0:
	set(nmr):
		_manual_restocks = nmr
		UI.trader_update_restock_cost.emit(get_restock_cost())
var _waves_since_restock: int = 0:
	set(nw):
		_waves_since_restock = nw
		UI.trader_update_waves_to_next_restock.emit(AUTO_RESTOCK_INTERVAL - _waves_since_restock)
var _has_unseen_stock: bool = false:
	set(value):
		_has_unseen_stock = value
		UI.trader_unseen_stock_changed.emit(_has_unseen_stock)

var _menu_open: bool = false
var _tutorial_next_manual_restock_stock: Array[Reward] = []

func _ready() -> void:
	set_process(false)
	set_process_mode(Node.PROCESS_MODE_ALWAYS)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("trader"):
		if _menu_open:
			close_menu()
		else:
			open_menu()

func initialise() -> void:
	#listen for wave progression
	if not Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.connect(_on_wave_ended)

	if not UI.trader_choice_selected.is_connected(purchase_item):
		UI.trader_choice_selected.connect(purchase_item)

	if not UI.trader_force_restock_requested.is_connected(force_restock):
		UI.trader_force_restock_requested.connect(force_restock)

	if _current_stock.is_empty():
		_generate_stock(false)

func start_game() -> void:
	_menu_open = false
	if _current_stock.is_empty():
		_generate_stock(false)

	UI.trader_update_waves_to_next_restock.emit(AUTO_RESTOCK_INTERVAL - _waves_since_restock)
	UI.trader_unseen_stock_changed.emit(_has_unseen_stock)

#--- public api ---

func open_menu() -> void:
	if is_instance_valid(Run.tutorials) and not Run.tutorials.can_open_trader():
		return
	_open_menu()

##opens the trader and clears the unseen-restock marker once the player has viewed it
func _open_menu() -> void:
	_menu_open = true
	_has_unseen_stock = false
	UI.trader_open.emit()

func close_menu() -> void:
	if is_instance_valid(Run.tutorials) and not Run.tutorials.can_close_trader():
		return
	_menu_open = false
	UI.trader_close.emit()

func get_stock() -> Array[Reward]:
	return _current_stock

##returns whether the current trader stock has appeared since the player last opened the menu
func has_unseen_stock() -> bool:
	return _has_unseen_stock

func get_restock_cost() -> float:
	return snappedf(pow(_manual_restocks, 2.0) * 2.0 + 2.0, 0.1)

func purchase_item(slot_index: int) -> bool:
	#push_warning(_current_stock, slot_index)
	if slot_index < 0 or slot_index >= _current_stock.size():
		return false

	var item = _current_stock[slot_index]
	if item == null:
		return false #already exhausted
	if is_instance_valid(Run.tutorials) and not Run.tutorials.can_purchase_trader_reward(item):
		return false

	if Run.player.flux < item.price:
		return false

	Run.player.flux -= item.price
	RewardService.apply_reward(item)
	item_purchased.emit(item, slot_index)

	_current_stock[slot_index] = null
	UI.trader_update_stock.emit(_current_stock)
	return true

func force_restock() -> bool:
	if is_instance_valid(Run.tutorials) and not Run.tutorials.can_force_restock():
		return false
	if Run.player.flux < get_restock_cost():
		return false

	Run.player.flux -= get_restock_cost()
	_manual_restocks += 1
	if _tutorial_next_manual_restock_stock.is_empty():
		_generate_stock(false)
	else:
		_set_stock(_tutorial_next_manual_restock_stock, false)
		_tutorial_next_manual_restock_stock.clear()
	stock_restocked.emit(true)
	return true

func set_tutorial_stock(rewards: Array[Reward], mark_unseen: bool) -> void: ##replaces the live trader stock with a fixed scripted set without touching the normal reward pool
	_set_stock(rewards, mark_unseen)

func set_tutorial_next_manual_restock_stock(rewards: Array[Reward]) -> void: ##queues one scripted stock result for the next manual restock, after which normal stock generation resumes
	_tutorial_next_manual_restock_stock.clear()
	for reward: Reward in rewards:
		if not is_instance_valid(reward):
			continue
		_tutorial_next_manual_restock_stock.append(reward)

#--- logic ---

func _on_wave_ended(_wave: int) -> void:
	_waves_since_restock += 1
	if _waves_since_restock >= AUTO_RESTOCK_INTERVAL:
		_waves_since_restock = 0
		_manual_restocks = 0
		_generate_stock(true)
		stock_restocked.emit(false)

##rebuilds trader stock and optionally marks the new restock as unseen by the player
func _generate_stock(mark_unseen: bool) -> void:
	var pool: Array[Reward] = RewardService.get_rewards(
		SLOT_COUNT,
		[
			Reward.Type.UNLOCK_TOWER,
			Reward.Type.ADD_RELIC,
			Reward.Type.ADD_RITE,
		]
	)
	if pool.is_empty():
		return
	_set_stock(pool, mark_unseen)

func _set_stock(rewards: Array[Reward], mark_unseen: bool) -> void:
	_current_stock.clear()
	for reward: Reward in rewards:
		_current_stock.append(reward)
	while _current_stock.size() < SLOT_COUNT:
		_current_stock.append(null)
	_has_unseen_stock = mark_unseen
	UI.trader_update_stock.emit(_current_stock)

func get_save_data() -> Dictionary:
	var data = {}
	data["manual_restocks"] = _manual_restocks
	data["waves_since"] = _waves_since_restock

	##serialize stock
	##we need to save the resource paths of the rewards to restore them
	#var stock_data = []
	#for item in _current_stock:
		#if item == null:
			#stock_data.append(null)
		#else:
			##assuming reward is a resource or has a way to identify itself.
			##if reward objects are runtime generated from definitions, we need to save their params.
			##best bet: save params + type.
			#var entry = {
				#"type": item.type,
				#"params": item.params,
				#"text": item.text
			#}
			#stock_data.append(entry)

	#data["stock"] = stock_data
	return data

func load_save_data(data: Dictionary) -> void:
	_manual_restocks = int(data.get("manual_restocks", 0))
	_waves_since_restock = int(data.get("waves_since", 0))

	_current_stock.clear()
	_generate_stock(false)
	#var stock_data = data.get("stock", [])

	#for entry in stock_data:
		#if entry == null:
			#_current_stock.append(null)
		#else:
			##reconstruct reward
			#var type = int(entry["type"])
			#var params = entry["params"]
			#var text = entry["text"]
			#var r = Reward.new(type, params, text)
			#_current_stock.append(r)
