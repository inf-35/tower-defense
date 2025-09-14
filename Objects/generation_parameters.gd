# generation_parameters.gd
extends Resource
class_name GenerationParameters

# --- terrain composition rules ---
@export_range(0.0, 1.0) var ruins_chance: float = 0.08

# --- feature placement pipeline ---
# this array defines the sequence of features to be placed.
# the generator will execute these rules in order.
@export var placement_rules: Array[PlacementRule] = []

func _init(_placement_rules: Array[PlacementRule] = []):
	self.placement_rules = _placement_rules
