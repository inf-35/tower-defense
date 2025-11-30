# generation_parameters.gd
extends Resource
class_name GenerationParameters

# --- feature placement pipeline ---
# this array defines the sequence of features to be placed.
# the generator will execute these rules in order.
@export var placement_rules: Array[ExpansionService.PlacementRule] = []
@export var terrain_gen_rules: Array[ExpansionService.TerrainGenRule] = []
