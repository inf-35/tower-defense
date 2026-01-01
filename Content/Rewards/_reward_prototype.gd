extends Resource
class_name RewardPrototype #see Reward

@export var id_name: String = "" ## optional unique ID for debugging
@export_multiline var description: String = ""

@export var type: Reward.Type = Reward.Type.UNLOCK_TOWER

@export var tower_type: Towers.Type = Towers.Type.VOID
@export var relic_data: RelicData
@export var rite_type: Towers.Type = Towers.Type.VOID
@export var flux_amount: int = 0

@export var base_weight: float = 100.0 
@export var bias_rules: Array[RewardBiasRule] = []

# converts this editor-friendly resource into the runtime Reward object
func generate_reward() -> Reward:
	var reward := Reward.new()
	reward.type = type
	reward.description = description
	reward.base_weight = base_weight
	reward.bias_rules = bias_rules
	
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
