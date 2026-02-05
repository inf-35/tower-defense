extends Node
class_name TraderService

# --- Configuration ---
const SLOT_COUNT: int = 3
const AUTO_RESTOCK_INTERVAL: int = 2 ## waves between free restocks

# --- State (Persistent) ---
# Each slot contains either a Reward resource or null (exhausted)
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
	# listen for wave progression
	if not Phases.wave_ended.is_connected(_on_wave_ended):
		Phases.wave_ended.connect(_on_wave_ended)
		
	UI.trader_choice_selected.connect(purchase_item)
	UI.trader_force_restock_requested.connect(force_restock)

	if _current_stock.is_empty():
		_generate_stock()
		
func start_game() -> void:
	_menu_open = false
	if _current_stock.is_empty():
		_generate_stock()
	
	UI.trader_update_waves_to_next_restock.emit(AUTO_RESTOCK_INTERVAL - _waves_since_restock)

# --- Public API ---

func open_menu():
	_menu_open = true
	UI.trader_open.emit()
	
func close_menu():
	_menu_open = false
	UI.trader_close.emit()

func get_stock() -> Array[Reward]:
	return _current_stock

func get_restock_cost() -> float:
	return pow(_manual_restocks, 2.0) * 2.0 + 4.0

func purchase_item(slot_index: int) -> bool:
	print(_current_stock, slot_index)
	if slot_index < 0 or slot_index >= _current_stock.size():
		return false

	var item = _current_stock[slot_index]
	if Player.flux < item.price:
		return false
		
	if item == null:
		return false #already exhausted
		
	Player.flux -= item.price
	RewardService.apply_reward(item)

	_current_stock[slot_index] = null
	UI.trader_update_stock.emit(_current_stock)
	return true

func force_restock() -> bool:
	if Player.flux < get_restock_cost():
		return false
		
	Player.flux -= get_restock_cost()
	_manual_restocks += 1
	_generate_stock()
	return true

# --- Logic ---

func _on_wave_ended(_wave: int) -> void:
	_waves_since_restock += 1
	if _waves_since_restock >= AUTO_RESTOCK_INTERVAL:
		_waves_since_restock = 0
		_manual_restocks = 0
		_generate_stock()

func _generate_stock() -> void:
	_current_stock.clear()
	
	# We want 3 items. RewardService usually generates options.
	# We can't use generate_and_present_choices because that affects the UI state directly.
	# We need a helper in RewardService to just GET random rewards.
	
	# Assuming RewardService has a pool we can sample, or we use a helper.
	# Implementation assumes RewardService.get_random_rewards(count) exists.
	# If not, we manually sample:
	
	var pool = RewardService.get_rewards(SLOT_COUNT)
	if pool.is_empty():
		return
	
	for reward in pool:
		_current_stock.append(reward)
		
	# Fill remaining with null if pool is tiny
	while _current_stock.size() < SLOT_COUNT:
		_current_stock.append(null)
		
	UI.trader_update_stock.emit(_current_stock)
	
func get_save_data() -> Dictionary:
	var data = {}
	data["manual_restocks"] = _manual_restocks
	data["waves_since"] = _waves_since_restock
	
	## Serialize Stock
	## We need to save the Resource Paths of the rewards to restore them
	#var stock_data = []
	#for item in _current_stock:
		#if item == null:
			#stock_data.append(null)
		#else:
			## Assuming Reward is a Resource or has a way to identify itself.
			## If Reward objects are runtime generated from definitions, we need to save their params.
			## Best bet: Save params + type.
			#var entry = {
				#"type": item.type,
				#"params": item.params,
				#"text": item.text
			#}
			#stock_data.append(entry)
			#
	#data["stock"] = stock_data
	return data

func load_save_data(data: Dictionary) -> void:
	_manual_restocks = int(data.get("manual_restocks", 0))
	_waves_since_restock = int(data.get("waves_since", 0))
	
	_current_stock.clear()
	_generate_stock()
	#var stock_data = data.get("stock", [])
	#
	#for entry in stock_data:
		#if entry == null:
			#_current_stock.append(null)
		#else:
			## Reconstruct Reward
			#var type = int(entry["type"])
			#var params = entry["params"]
			#var text = entry["text"]
			#var r = Reward.new(type, params, text)
			#_current_stock.append(r)
			
