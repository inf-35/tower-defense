extends Node
class_name TraderService

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

var _menu_open: bool = false

func _ready() -> void:
	set_process(false)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("trader"):
		_menu_open = not _menu_open
		if _menu_open:
			UI.trader_open.emit()
		else:
			UI.trader_close.emit()

func initialise() -> void:
	#listen for wave progression
	if not Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.connect(_on_wave_ended)

	if not UI.trader_choice_selected.is_connected(purchase_item):
		UI.trader_choice_selected.connect(purchase_item)

	if not UI.trader_force_restock_requested.is_connected(force_restock):
		UI.trader_force_restock_requested.connect(force_restock)

	if _current_stock.is_empty():
		_generate_stock()

func start_game() -> void:
	_menu_open = false
	if _current_stock.is_empty():
		_generate_stock()

	UI.trader_update_waves_to_next_restock.emit(AUTO_RESTOCK_INTERVAL - _waves_since_restock)

#--- public api ---

func open_menu() -> void:
	_menu_open = true
	UI.trader_open.emit()

func close_menu() -> void:
	_menu_open = false
	UI.trader_close.emit()

func get_stock() -> Array[Reward]:
	return _current_stock

func get_restock_cost() -> float:
	return snappedf(pow(_manual_restocks, 2.0) * 2.0 + 2.0, 0.1)

func purchase_item(slot_index: int) -> bool:
	#push_warning(_current_stock, slot_index)
	if slot_index < 0 or slot_index >= _current_stock.size():
		return false

	var item = _current_stock[slot_index]
	if item == null:
		return false #already exhausted

	if Run.player.flux < item.price:
		return false

	Run.player.flux -= item.price
	RewardService.apply_reward(item)

	_current_stock[slot_index] = null
	UI.trader_update_stock.emit(_current_stock)
	return true

func force_restock() -> bool:
	if Run.player.flux < get_restock_cost():
		return false

	Run.player.flux -= get_restock_cost()
	_manual_restocks += 1
	_generate_stock()
	return true

#--- logic ---

func _on_wave_ended(_wave: int) -> void:
	_waves_since_restock += 1
	if _waves_since_restock >= AUTO_RESTOCK_INTERVAL:
		_waves_since_restock = 0
		_manual_restocks = 0
		_generate_stock()

func _generate_stock() -> void:
	_current_stock.clear()

	#we want 3 items. rewardservice usually generates options.
	#we can't use generate_and_present_choices because that affects the ui state directly.
	#we need a helper in rewardservice to just get random rewards.

	#assuming rewardservice has a pool we can sample, or we use a helper.
	#implementation assumes rewardservice.get_random_rewards(count) exists.
	#if not, we manually sample:

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

	for reward in pool:
		_current_stock.append(reward)

	#fill remaining with null if pool is tiny
	while _current_stock.size() < SLOT_COUNT:
		_current_stock.append(null)

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
	_generate_stock()
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
