# reward_data.gd
extends Resource
class_name RewardData

# --- definition of the reward's effect ---
enum RewardType {
	ADD_FLUX,
	UNLOCK_TOWER,
	APPLY_GLOBAL_MODIFIER,
	# add other types of reward effects here
}
@export var type: RewardType

# --- data for the effect ---
# this dictionary holds the specific parameters for the chosen type
# e.g., for ADD_FLUX: {"amount": 50}
# e.g., for UNLOCK_TOWER: {"tower_type": Towers.Type.CANNON}
@export var params: Dictionary = {}

# --- presentation data for the ui ---
@export var title: String = "Reward Title"
@export_multiline var description: String = "Reward description."
