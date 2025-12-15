# reward_service.gd (Autoload Singleton)
extends Node

signal reward_process_complete

# --- configuration ---
const REWARD_DIRECTORY: String = "res://Content/Rewards/"

# populated automatically at startup
var reward_pool: Array[Reward] = []

# --- state ---
var is_choosing_reward: bool = false
var _current_reward_options_by_id: Dictionary[int, Reward] = {}

func _ready():
	_load_all_rewards()
	set_process(false)

# --- loading logic ---

func _load_all_rewards() -> void:
	reward_pool.clear()
	print("RewardService: Loading rewards from ", REWARD_DIRECTORY)
	_scan_directory_recursive(REWARD_DIRECTORY)
	print("RewardService: Loaded ", reward_pool.size(), " rewards.")

func _scan_directory_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		push_error("RewardService: Failed to open directory: " + path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir():
			if not file_name.begins_with("."): #ignore . and ..
				# recursively scan subdirectories
				_scan_directory_recursive(path + file_name + "/")
		elif (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var full_path: String = path + file_name
			var resource: Resource = load(full_path)
			
			if resource is RewardPrototype:
				# convert the Resource into the runtime instance and add to pool
				reward_pool.append(resource.generate_reward())
			else:
				pass
				
		file_name = dir.get_next()
	
	dir.list_dir_end()

# --- public api ---

func generate_and_present_choices(choice_count: int, filter = null) -> void: ##where filter is the Reward.Type being selected for
	if reward_pool.is_empty():
		push_warning("RewardService: Reward pool is empty. Cannot generate choices.")
		reward_process_complete.emit()
		return

	_current_reward_options_by_id.clear()
	var available_rewards: Array[Reward] = get_rewards_by_type(filter) if filter else reward_pool.duplicate()
	available_rewards.shuffle()
	
	for i: int in choice_count:
		if available_rewards.size() - 1 < i:
			break
		_current_reward_options_by_id[i] = available_rewards[i]
		
	is_choosing_reward = true
	
	UI.display_reward_choices.emit(_current_reward_options_by_id.values())

func get_rewards_by_type(type_filter: Reward.Type) -> Array[Reward]:
	return reward_pool.filter(func(reward: Reward): return reward.type == type_filter)

func select_reward(choice_id: int) -> void:
	if not _current_reward_options_by_id.has(choice_id):
		push_error("RewardService: Invalid choice_id received: " + str(choice_id))
		reward_process_complete.emit()
		return

	var chosen_reward: Reward = _current_reward_options_by_id[choice_id]
	apply_reward(chosen_reward)
	
	_current_reward_options_by_id.clear() 
	is_choosing_reward = false
	
	UI.hide_reward_choices.emit()
	reward_process_complete.emit()
	
func apply_reward(reward: Reward) -> void:
	match reward.type:
		Reward.Type.ADD_FLUX:
			var amount: int = reward.params.get(ID.Rewards.FLUX_AMOUNT, 0)
			Player.flux += amount
			
		Reward.Type.UNLOCK_TOWER:
			var tower_type: Towers.Type = reward.params.get(ID.Rewards.TOWER_TYPE, Towers.Type.VOID)
			if tower_type != Towers.Type.VOID:
				Player.unlock_tower(tower_type)

		Reward.Type.ADD_RELIC:
			var relic = reward.params.get(ID.Rewards.RELIC)
			if relic is RelicData:
				Player.add_relic(relic)
