# reward_service.gd (Autoload Singleton)
extends Node

signal reward_process_complete

# --- configuration ---
@export var reward_pool: Array[RewardData] = []

# --- state ---
# this now stores the choices presented to the player, indexed by an integer ID
var _current_reward_options_by_id: Dictionary[int, RewardData] = {}

# the main public API called by Phases.gd
func generate_and_present_choices(choice_count: int) -> void:
	if reward_pool.is_empty():
		push_warning("RewardService: Reward pool is empty. Cannot generate choices.")
		reward_process_complete.emit()
		return

	_current_reward_options_by_id.clear()
	var available_rewards: Array[RewardData] = reward_pool.duplicate()
	available_rewards.shuffle()
	
	var options_to_display: Array[Dictionary] = []
	for i: int in min(choice_count, available_rewards.size()):
		var reward: RewardData = available_rewards[i]
		# store the reward by its index, which will be its ID
		_current_reward_options_by_id[i] = reward
		# pack the reward and its ID for the UI
		options_to_display.append({"id": i, "data": reward})

	# command the UI to display these specific reward options
	UI.display_reward_options.emit(options_to_display)

# this function now accepts an integer ID
func select_reward(choice_id: int) -> void:
	# look up the reward data using the provided ID
	if not _current_reward_options_by_id.has(choice_id):
		push_error("RewardService: Invalid choice_id received: " + str(choice_id))
		reward_process_complete.emit()
		return

	var chosen_reward: RewardData = _current_reward_options_by_id[choice_id]
	_apply_reward(chosen_reward)
	
	_current_reward_options_by_id.clear() # clear the state after a choice is made
	UI.hide_reward_options.emit()
	reward_process_complete.emit()

# internal logic for executing the reward's effect
func _apply_reward(reward: RewardData) -> void:
	match reward.type:
		RewardData.RewardType.ADD_FLUX:
			var amount: int = reward.params.get("amount", 0)
			Player.flux += amount
			
		RewardData.RewardType.UNLOCK_TOWER:
			var tower_type: Towers.Type = reward.params.get("tower_type", Towers.Type.VOID)
			if tower_type != Towers.Type.VOID:
				Player.unlock_tower(tower_type)

		RewardData.RewardType.APPLY_GLOBAL_MODIFIER:
			push_warning("RewardService: APPLY_GLOBAL_MODIFIER not yet implemented.")
