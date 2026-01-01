#reward.gd - see RewardService for implementation and Rewards for data
extends Resource
class_name Reward

enum Type {
	ADD_FLUX,
	UNLOCK_TOWER,
	ADD_RELIC,
	ADD_RITE,
	
	EXPORT #workaround, this tells the initialiser that the reward is defined in inspector
}

@export var type: Type
@export var tower_type: Towers.Type
@export var relic: RelicData
@export var rite_type: Towers.Type
@export var flux_amount: float

@export var base_weight: float = 100.0 ## higher = more common, 0 = disabled.
@export var bias_rules: Array[RewardBiasRule] = []

@export var title: String = "dappled things" #used for terrain expansion previews and such
@export_multiline var description: String = "Reward description"
