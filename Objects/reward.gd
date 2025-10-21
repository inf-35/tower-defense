#reward.gd - see RewardService for implementation and Rewards for data
extends Resource
class_name Reward

enum Type {
	ADD_FLUX,
	UNLOCK_TOWER,
	ADD_RELIC,
	
	EXPORT #workaround, this tells the initialiser that the reward is defined in inspector
}

@export var type: Type
@export var params: Dictionary = {
	#examples
	ID.Rewards.FLUX_AMOUNT : 0.0,
	ID.Rewards.TOWER_TYPE : Towers.Type.TURRET,
	ID.Rewards.RELIC : Relics.TOWER_SPEED_UP,
}

@export_multiline var description: String = "Reward description"

func _init(_type: Type = Type.EXPORT, _params: Dictionary = {}, _description: String = ""):
	if _type != Type.EXPORT: self.type = _type
	if not _params.is_empty(): self.params = _params
	description = _description
