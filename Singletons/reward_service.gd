#reward_service.gd (autoload singleton)
extends Node

signal reward_process_complete

#--- configuration ---
const REWARD_DIRECTORY: String = "res://Content/Rewards/"
const DEFAULT_CHOICE_TITLE: String = "Choose a reward"

#populated automatically at startup
var reward_pool: Array[Reward] = []

#--- state ---
var is_choosing_reward: bool = false
var _current_reward_options_by_id: Dictionary[int, Reward] = {}
var rerolls_this_phase: int = 0:
	set(nr):
		rerolls_this_phase = nr
		UI.update_reroll_cost.emit(get_reroll_cost())

var _last_choice_count: int
var _last_type_filter: Array[Reward.Type]
var current_choice_title: String = DEFAULT_CHOICE_TITLE
var current_reroll_enabled: bool = true
var _current_choice_config: RewardChoiceConfig
var _owns_choice_signal: bool = false

func _ready() -> void:
	_load_all_rewards()
	set_process(false)

func _load_all_rewards() -> void:
	reward_pool.clear()
	print("RewardService: Loading rewards from ", REWARD_DIRECTORY)
	_scan_directory_recursive(REWARD_DIRECTORY)
	print("RewardService: Loaded ", reward_pool.size(), " rewards.")

	for reward in reward_pool:
		if reward.type == Reward.Type.UNLOCK_TOWER:
			reward.price = snappedf(randf_range(6.0, 12.0), 0.1)
		else:
			reward.price = snappedf(randf_range(3.0, 7.0), 0.1)

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
				#recursively scan subdirectories
				_scan_directory_recursive(path + file_name + "/")
		elif (file_name.ends_with(".tres") or file_name.ends_with(".res") or file_name.ends_with(".tres.remap")):
			file_name = file_name.trim_suffix(".remap") #trim remap from file paths, if it exists (for web builds)
			var full_path: String = path + file_name
			var resource: Resource = load(full_path)

			if resource is RewardPrototype:
				#convert the resource into the runtime instance and add to pool
				reward_pool.append(resource.generate_reward())

				if resource.type == Reward.Type.ADD_RELIC:
					Relics.relics[resource.relic_data.type] = resource.relic_data
			else:
				pass

		file_name = dir.get_next()

	dir.list_dir_end()

func generate_and_present_choices(choice_count: int, type_filter: Array[Reward.Type] = []) -> bool: ##uses the global reward pool to roll a standard choice screen
	var config := RewardChoiceConfig.new()
	config.choice_count = choice_count
	config.type_filter = type_filter
	config.allow_reroll = true
	config.include_global_pool = true
	return _present_rewards_from_config(config, false)

func generate_and_present_configured_choices(config: RewardChoiceConfig) -> bool: ##uses an authored config and lets RewardService own the reward selection flow directly
	return _present_rewards_from_config(config, true)

func reroll() -> void: ##re-rolls the most recently presented reward config
	if not is_instance_valid(_current_choice_config):
		return
	if not _present_rewards_from_config(_current_choice_config, _owns_choice_signal):
		return
	rerolls_this_phase += 1

func get_rewards(choice_count: int, type_filter: Array[Reward.Type] = []) -> Array[Reward]: ##rolls rewards from the global reward pool, optionally constrained by reward type
	return get_rewards_from_candidates(choice_count, _build_global_candidates(type_filter))

func get_rewards_from_candidates(choice_count: int, candidate_rewards: Array[Reward]) -> Array[Reward]: ##rolls rewards from an arbitrary candidate pool while preserving the normal ownership and weighting rules
	return _roll_rewards(candidate_rewards, choice_count)

func get_rewards_by_type(type_filter: Reward.Type) -> Array[Reward]:
	return reward_pool.filter(func(reward: Reward): return reward.type == type_filter)

func get_reroll_cost() -> float:
	return pow(2, rerolls_this_phase) + 2.0

func _calculate_reward_weight(reward: Reward) -> float:
	if _player_already_has_reward(reward):
		return 0.0

	var final_weight: float = reward.base_weight
	if reward.type == Reward.Type.UNLOCK_TOWER:
		final_weight = maxf(final_weight, 200.0)

	for rule: RewardBiasRule in reward.bias_rules:
		final_weight *= rule.get_multiplier()

		#optimization: if weight hits 0, stop calculating
		if final_weight <= 0.0:
			return 0.0

	return final_weight

func _player_already_has_reward(reward: Reward) -> bool:
	match reward.type:
		Reward.Type.UNLOCK_TOWER:
			return reward.tower_type != Towers.Type.VOID and Run.player.is_tower_unlocked(reward.tower_type)
		Reward.Type.ADD_RELIC:
			return _player_has_relic_type(reward.relic.type) if is_instance_valid(reward.relic) else false
		_:
			return false

func _player_has_relic_type(relic_type: RelicData.Type) -> bool:
	for relic: RelicData in Run.player.active_relics:
		if is_instance_valid(relic) and relic.type == relic_type:
			return true
	return false

func _pick_weighted_index(weights: Array[float], total_weight: float) -> int:
	var roll: float = randf_range(0.0, total_weight)
	var accumulated: float = 0.0

	for i: int in weights.size():
		accumulated += weights[i]
		if roll <= accumulated:
			return i

	push_warning("Reward service: roll failed!")
	return weights.size() - 1 #fallback

func select_reward(choice_id: int) -> void: #concludes reward phase
	if not _current_reward_options_by_id.has(choice_id):
		push_error("RewardService: Invalid choice_id received: " + str(choice_id))
		_disconnect_owned_choice_signal()
		reward_process_complete.emit()
		return

	var chosen_reward: Reward = _current_reward_options_by_id[choice_id]
	apply_reward(chosen_reward)

	_current_reward_options_by_id.clear()
	is_choosing_reward = false
	rerolls_this_phase = 0
	current_choice_title = DEFAULT_CHOICE_TITLE
	current_reroll_enabled = true
	_current_choice_config = null
	_disconnect_owned_choice_signal()

	UI.hide_reward_choices.emit()
	reward_process_complete.emit()

func apply_reward(reward: Reward) -> void:
	match reward.type:
		Reward.Type.ADD_FLUX:
			var amount: float = reward.flux_amount
			Run.player.flux += amount

		Reward.Type.UNLOCK_TOWER:
			var tower_type: Towers.Type = reward.tower_type
			if tower_type != Towers.Type.VOID and not Run.player.is_tower_unlocked(tower_type):
				Run.player.unlock_tower(tower_type)

		Reward.Type.ADD_RELIC:
			var relic: RelicData = reward.relic
			if relic and not _player_has_relic_type(relic.type):
				Run.player.add_relic(relic)

		Reward.Type.ADD_RITE:
			var rite_type: Towers.Type = reward.rite_type
			Run.player.add_rite(rite_type, 1)

func _present_rewards_from_config(config: RewardChoiceConfig, owns_choice_signal: bool) -> bool:
	if not is_instance_valid(config):
		return false

	var rewards: Array[Reward] = _roll_rewards(_build_reward_candidates(config), config.choice_count)
	if rewards.is_empty():
		return false

	_current_reward_options_by_id.clear()
	for i: int in range(rewards.size()):
		_current_reward_options_by_id[i] = rewards[i]

	is_choosing_reward = true
	_last_choice_count = config.choice_count
	_last_type_filter = config.type_filter
	current_choice_title = config.title if config.title != "" else DEFAULT_CHOICE_TITLE
	current_reroll_enabled = config.allow_reroll
	_current_choice_config = config
	_owns_choice_signal = owns_choice_signal

	if owns_choice_signal and not UI.choice_selected.is_connected(_on_owned_choice_selected):
		UI.choice_selected.connect(_on_owned_choice_selected)

	UI.display_reward_choices.emit(_current_reward_options_by_id.values())
	return true

func _build_reward_candidates(config: RewardChoiceConfig) -> Array[Reward]:
	var candidates: Array[Reward] = []

	if config.include_global_pool:
		candidates.append_array(_build_global_candidates(config.type_filter))

	for candidate: Reward in config.candidate_rewards:
		if not is_instance_valid(candidate):
			continue
		candidates.append(candidate.duplicate_deep())

	return candidates

func _build_global_candidates(type_filter: Array[Reward.Type]) -> Array[Reward]:
	var candidates: Array[Reward] = []
	for reward: Reward in reward_pool:
		if (not type_filter.is_empty()) and (not type_filter.has(reward.type)):
			continue
		candidates.append(reward)
	return candidates

func _roll_rewards(candidate_rewards: Array[Reward], choice_count: int) -> Array[Reward]:
	var rewards: Array[Reward] = []
	var candidates: Array[Reward] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0

	for reward: Reward in candidate_rewards:
		if not is_instance_valid(reward):
			continue
		if _player_already_has_reward(reward):
			continue

		var weight: float = _calculate_reward_weight(reward)
		if weight <= 0.0:
			continue

		candidates.append(reward)
		weights.append(weight)
		total_weight += weight

	for _index: int in range(choice_count):
		if total_weight <= 0.0:
			break

		var chosen_index: int = _pick_weighted_index(weights, total_weight)
		rewards.append(candidates[chosen_index])
		total_weight -= weights[chosen_index]
		candidates.remove_at(chosen_index)
		weights.remove_at(chosen_index)

	return rewards

func _on_owned_choice_selected(choice_id: int) -> void:
	if not _owns_choice_signal:
		return
	if not is_choosing_reward:
		return
	select_reward(choice_id)

func _disconnect_owned_choice_signal() -> void:
	if _owns_choice_signal and UI.choice_selected.is_connected(_on_owned_choice_selected):
		UI.choice_selected.disconnect(_on_owned_choice_selected)
	_owns_choice_signal = false
