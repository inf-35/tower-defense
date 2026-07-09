extends Resource
class_name RewardPrototype #see Reward

@export var id_name: String = "" ##optional unique id for debugging
@export var title: String = "" ##optional authored title copied onto the runtime reward for ui that wants a named reward
@export_multiline var description: String = ""

@export var type: Reward.Type = Reward.Type.UNLOCK_TOWER

@export var tower_type: Towers.Type = Towers.Type.VOID
@export var relic_data: RelicData
@export var rite_type: Towers.Type = Towers.Type.VOID
@export var flux_amount: int = 0

@export var base_rarity: Reward.Rarity = Reward.Rarity.UNCOMMON
@export var weight_scale: float = 1.0
@export var tag_rules: Array[RewardTagRule] = []
@export var tower_rules: Array[RewardTowerRule] = []

func generate_reward() -> Reward: ##converts this editor-friendly resource into the runtime reward object
	var reward := Reward.new()
	reward.type = type
	reward.title = title
	reward.description = description
	reward.base_rarity = base_rarity
	reward.weight_scale = weight_scale
	reward.tag_rules = tag_rules
	reward.tower_rules = tower_rules

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
