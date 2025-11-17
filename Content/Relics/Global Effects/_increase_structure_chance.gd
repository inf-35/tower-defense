# ruin_spawn_chance_effect.gd
extends GlobalEffect
class_name StructureSpawnChanceEffect

# --- configuration (designer-friendly) ---
# a designer can set this to 1.5 for a +50% increase, or 2.0 for a 100% increase, etc.
@export var structure_chance_multiplier: float = 1.0

# this function is called by the GlobalModifierService when the relic is acquired
func initialise() -> void:
	# connect to the global signal from the broker service
	References.terrain_generating.connect(_on_generation_parameters_requested)

# this is the core of the relic's logic, triggered by the signal
func _on_generation_parameters_requested(params: GenerationParameters) -> void:
	# directly modify the 'ruins_chance' property of the parameters object.
	# because objects are passed by reference, this modification will be seen
	# by the ExpansionService after the signal is processed.
	params.ruins_chance *= structure_chance_multiplier
	
	# for safety, ensure the value doesn't go above 100%
	params.ruins_chance = min(params.ruins_chance, 1.0)
