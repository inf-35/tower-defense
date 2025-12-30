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
@export var rite_type: Towers.Type = Towers.Type.VOID
@export var flux_amount: int = 0

# converts this editor-friendly resource into the runtime Reward object
func generate_reward() -> Reward:
	var reward := Reward.new()
	reward.type = type
	reward.description = description
	
	match type:
		Reward.Type.UNLOCK_TOWER:
			reward.tower_type = tower_type
		Reward.Type.ADD_RELIC:
			reward.relic = relic_data
		Reward.Type.ADD_RITE:
			reward.rite_type = rite_type
		Reward.Type.ADD_FLUX:
			reward.flux_amount = flux_amount
			
	return reward
