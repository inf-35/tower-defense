#reward.gd - see RewardService for implementation
extends Resource
class_name Reward

enum Type {
	ADD_FLUX,
	UNLOCK_TOWER,
	APPLY_MODIFIER,
}

@export var type: Type
@export var params: Dictionary = {
	#examples
	ID.Rewards.FLUX_AMOUNT : 0.0,
	ID.Rewards.TOWER_TYPE : Towers.Type.TURRET,
}

func _init(_type: Type, _params: Dictionary):
	self.type = _type
	self.params = _params
