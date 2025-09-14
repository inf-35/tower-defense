# reward_service.gd (Autoload Singleton)
extends Node

signal reward_process_complete
# --- configuration ---
@export var reward_pool: Array[Reward] = [
	Reward.new(
		Reward.Type.UNLOCK_TOWER,
		{ID.Rewards.TOWER_TYPE: Towers.Type.CANNON}
	),
	Reward.new(
		Reward.Type.UNLOCK_TOWER,
		{ID.Rewards.TOWER_TYPE: Towers.Type.FROST_TOWER}
	),
	Reward.new(
		Reward.Type.UNLOCK_TOWER,
		{ID.Rewards.TOWER_TYPE: Towers.Type.CANNON}
	)
]
# --- state ---
var is_choosing_reward: bool = false
# this now stores the choices presented to the player, indexed by an integer ID
var _current_reward_options_by_id: Dictionary[int, Reward] = {}

func _ready():
	set_process(false)
# the main public API called by Phases.gd
func generate_and_present_choices(choice_count: int) -> void:
	if reward_pool.is_empty():
		push_warning("RewardService: Reward pool is empty. Cannot generate choices.")
		reward_process_complete.emit()
		return

	_current_reward_options_by_id.clear()
	var available_rewards: Array[Reward] = reward_pool.duplicate()
	available_rewards.shuffle()
	
	for i: int in choice_count:
		if available_rewards.size() - 1 < i:
			break
		_current_reward_options_by_id[i] = available_rewards[i]
		
	is_choosing_reward = true
	
	UI.display_reward_choices.emit(_current_reward_options_by_id.values())

# this function now accepts an integer ID, called by PhaseManager
func select_reward(choice_id: int) -> void:
	# look up the reward data using the provided ID
	if not _current_reward_options_by_id.has(choice_id):
		push_error("RewardService: Invalid choice_id received: " + str(choice_id))
		reward_process_complete.emit()
		return

	var chosen_reward: Reward = _current_reward_options_by_id[choice_id]
	apply_reward(chosen_reward)
	
	_current_reward_options_by_id.clear() # clear the state after a choice is made
	is_choosing_reward = false
	
	UI.hide_reward_choices.emit()
	reward_process_complete.emit()
	
# internal logic for executing the reward's effect
func apply_reward(reward: Reward) -> void:
	match reward.type:
		Reward.Type.ADD_FLUX:
			var amount: int = reward.params.get(ID.Rewards.FLUX_AMOUNT, 0)
			Player.flux += amount
			
		Reward.Type.UNLOCK_TOWER:
			var tower_type: Towers.Type = reward.params.get(ID.Rewards.TOWER_TYPE, Towers.Type.VOID)
			if tower_type != Towers.Type.VOID:
				Player.unlock_tower(tower_type)

		Reward.Type.APPLY_MODIFIER:
			push_warning("RewardService: APPLY_GLOBAL_MODIFIER not yet implemented.")
