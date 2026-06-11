extends Resource
class_name RewardChoiceConfig

@export var title: String = "Choose a reward" ##title shown on the shared reward panel while this choice set is active
@export var choice_count: int = 3 ##number of rewards rolled and shown to the player
@export var allow_reroll: bool = false ##whether the shared reroll button is available for this reward source
@export var include_global_pool: bool = true ##whether the global reward pool should be merged into the local candidate list
@export var type_filter: Array[Reward.Type] = [] ##optional filter applied to global-pool rewards when include_global_pool is enabled
@export var candidate_rewards: Array[Reward] = [] ##explicit authored candidates that can supplement or replace the global pool
