#reward.gd - see RewardService for implementation
extends Resource
class_name Reward

enum Type {
	ADD_FLUX,
	UNLOCK_TOWER,
	APPLY_MODIFIER,
	
	EXPORT #workaround, this tells the initialiser that the reward is defined in inspector
}

@export var type: Type
@export var params: Dictionary = {
	#examples
	ID.Rewards.FLUX_AMOUNT : 0.0,
	ID.Rewards.TOWER_TYPE : Towers.Type.TURRET,
}

func _init(_type: Type = Type.EXPORT, _params: Dictionary = {}):
	if _type != Type.EXPORT: self.type = _type
	if not _params.is_empty(): self.params = _params
