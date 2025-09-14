# placement_rule.gd
extends Resource
class_name PlacementRule

# defines where the feature can be placed relative to the new landmass
enum PlacementLogic {
	ANYWHERE, # can be placed on any available tile
	EDGE      # must be on a tile adjacent to the existing island or sea
}
@export var placement: PlacementLogic = PlacementLogic.EDGE

# the tower type to place (e.g., BREACH_SEED, ANOMALY)
@export var tower_type: Towers.Type

# how many instances of this feature to attempt to place
@export var count: int = 1

# the initial_state packet to apply to the generated tower
# e.g., {"seed_duration_waves": 2}
@export var initial_state: Dictionary
