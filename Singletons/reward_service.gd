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
		elif (file_name.ends_with(".tres") or file_name.ends_with(".res") or file_name.ends_with(".tres.remap")):
			file_name = file_name.trim_suffix(".remap") #trim remap from file paths, if it exists (for web builds)
			var full_path: String = path + file_name
			var resource: Resource = load(full_path)
			
			if resource is RewardPrototype:
				# convert the Resource into the runtime instance and add to pool
				reward_pool.append(resource.generate_reward())
				
				if resource.type == Reward.Type.ADD_RELIC:
					Relics.relics[resource.relic_data.type] = resource.relic_data
			else:
				pass
				
		file_name = dir.get_next()
	
	dir.list_dir_end()

# --- public api ---
#
#func generate_and_present_choices(choice_count: int, filter = null) -> void: ##where filter is the Reward.Type being selected for
	#if reward_pool.is_empty():
		#push_warning("RewardService: Reward pool is empty. Cannot generate choices.")
		#reward_process_complete.emit()
		#return
#
	#_current_reward_options_by_id.clear()
	#var available_rewards: Array[Reward] = get_rewards_by_type(filter) if filter else reward_pool.duplicate()
	#available_rewards.shuffle()
	#
	#var chosen_rewards: int = 0
	#var i: int = 0
	#while chosen_rewards < choice_count:
		#if available_rewards.size() - 1 < i:
			#break
		#
		#var current_reward: Reward = available_rewards[i]
		##reject towers, relics and rites already held by the player
		#if current_reward.type == Reward.Type.UNLOCK_TOWER and Player.unlocked_towers.has(current_reward.tower_type):
			#i += 1
			#continue
		#elif current_reward.type == Reward.Type.ADD_RELIC and Player.active_relics.has(current_reward.relic):
			#i += 1
			#continue
		#elif current_reward.type == Reward.Type.ADD_RITE and Player.get_tower_limit(current_reward.rite_type) > 0:
			#i += 1
			#continue
#
		#_current_reward_options_by_id[chosen_rewards] = available_rewards[i]
		#chosen_rewards += 1
		#i += 1
		#
	#is_choosing_reward = true
	#
	#UI.display_reward_choices.emit(_current_reward_options_by_id.values())

func generate_and_present_choices(choice_count: int, type_filter: Array[Reward.Type] = []) -> void:
	var rewards: Array[Reward] = get_rewards(choice_count, type_filter)
	
	for i: int in len(rewards):
		_current_reward_options_by_id[i] = rewards[i]

	is_choosing_reward = true
	UI.display_reward_choices.emit(_current_reward_options_by_id.values())

func get_rewards(choice_count: int, type_filter: Array[Reward.Type] = []) -> Array[Reward]:
	var rewards: Array[Reward] = []
	
	var candidates: Array[Reward] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0
	
	# loop through all loaded rewards
	for reward: Reward in reward_pool:
		# filter by requested type
		if (not type_filter.is_empty()) and (not type_filter.has(reward.type)):
			continue

		var weight: float = 100.0
		weight = _calculate_reward_weight(reward)

		if weight > 0.0:
			candidates.append(reward)
			weights.append(weight)
			total_weight += weight
	
	for i: int in choice_count:
		if total_weight <= 0: break
		
		var chosen_index: int = _pick_weighted_index(weights, total_weight)
		var chosen_reward: Reward = candidates[chosen_index]
	
		rewards.append(chosen_reward)
		# remove from pool to prevent duplicates in the same choice screen
		total_weight -= weights[chosen_index]
		candidates.remove_at(chosen_index)
		weights.remove_at(chosen_index)
		
	return rewards

func get_rewards_by_type(type_filter: Reward.Type) -> Array[Reward]:
	return reward_pool.filter(func(reward: Reward): return reward.type == type_filter)
	
func _calculate_reward_weight(reward: Reward) -> float:
	var final_weight: float = reward.base_weight
	
	for rule: RewardBiasRule in reward.bias_rules:
		final_weight *= rule.get_multiplier()
		
		# optimization: If weight hits 0, stop calculating
		if final_weight <= 0.0:
			return 0.0
			
	return final_weight

func _pick_weighted_index(weights: Array[float], total_weight: float) -> int:
	var roll: float = randf_range(0.0, total_weight)
	var accumulated: float = 0.0
	
	for i: int in weights.size():
		accumulated += weights[i]
		if roll <= accumulated:
			return i
	
	push_warning("Reward service: roll failed!")
	return weights.size() - 1 # fallback

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
			var amount: float = reward.flux_amount
			Player.flux += amount
			
		Reward.Type.UNLOCK_TOWER:
			var tower_type: Towers.Type = reward.tower_type
			if tower_type != Towers.Type.VOID:
				Player.unlock_tower(tower_type)

		Reward.Type.ADD_RELIC:
			var relic: RelicData = reward.relic
			if relic:
				Player.add_relic(relic)
		
		Reward.Type.ADD_RITE:
			var rite_type: Towers.Type = reward.rite_type
			Player.add_rite(rite_type, 1)
