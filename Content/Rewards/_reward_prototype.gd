extends Resource
class_name RewardPrototype #see Reward

@export_group("Identity")
@export var id_name: String = "" ## optional unique ID for debugging
@export_multiline var description: String = ""

@export_group("Type Settings")
@export var type: Reward.Type = Reward.Type.UNLOCK_TOWER

@export_subgroup("Parameters")
@export var tower_type: Towers.Type = Towers.Type.VOID
@export var relic_data: RelicData
@export var flux_amount: int = 0

# converts this editor-friendly resource into the runtime Reward object
func generate_reward() -> Reward:
	var params: Dictionary = {}
	
	match type:
		Reward.Type.UNLOCK_TOWER:
			params[ID.Rewards.TOWER_TYPE] = tower_type
		Reward.Type.ADD_RELIC:
			params[ID.Rewards.RELIC] = relic_data
		Reward.Type.ADD_FLUX:
			params[ID.Rewards.FLUX_AMOUNT] = flux_amount

	return Reward.new(type, params, description)
