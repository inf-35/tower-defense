# anomaly_data.gd
extends Resource
class_name AnomalyData

# the reward this anomaly will grant upon completion
@export var reward: Reward

# the number of waves the adjacency condition must be met
@export var waves_to_charge: int = 3

# --- presentation data for the ui ---
@export var title: String = "Unstable Anomaly"
@export_multiline var description: String = "Maintain adjacent towers for %d waves to stabilize and claim its reward."

func _init(_reward: Reward = null, _waves_to_charge: int = 2):
	reward = _reward
	waves_to_charge = _waves_to_charge
