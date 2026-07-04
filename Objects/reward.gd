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

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	DEBUG,
	NONE
}

@export var type: Type
@export var tower_type: Towers.Type
@export var relic: RelicData
@export var rite_type: Towers.Type
@export var flux_amount: float

@export var base_rarity: Rarity = Rarity.UNCOMMON
@export var weight_scale: float = 1.0 ##post-rarity multiplier for authored edge cases such as gold bundles
@export var tag_rules: Array[RewardTagRule] = []
@export var tower_rules: Array[RewardTowerRule] = []

@export var price: float = 0.0 ##in gold!

@export var title: String = "dappled things" #used for terrain expansion previews and such
@export_multiline var description: String = "Reward description"

##resolves the authored rarity enum into the final base reward weight before tag adjustments
func get_base_weight() -> float:
	return get_rarity_weight(base_rarity) * weight_scale

##maps the shared authored rarity levels into concrete reward-pool weights
static func get_rarity_weight(rarity: Rarity) -> float:
	match rarity:
		Rarity.COMMON:
			return 200.0
		Rarity.UNCOMMON:
			return 100.0
		Rarity.RARE:
			return 50.0
		Rarity.DEBUG:
			return 500000.0
	return 100.0
