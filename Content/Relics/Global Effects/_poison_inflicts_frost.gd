# poison_inflicts_frost_effect.gd
extends GlobalEffect
class_name PoisonInflictsFrostEffect

# this is a stateless effect, so it has no @export vars or state dictionaries

func initialise() -> void:
	# connect to a new global signal that fires for every single hit taken in the game
	# this is a more scalable approach than connecting to every unit individually
	References.unit_took_hit.connect(_on_unit_took_hit)

# this function is the core of the relic's logic
func _on_unit_took_hit(unit: Unit, hit_data: HitData) -> void:
	# check if the hit contains any stacks of the POISON status effect
	if not hit_data.status_effects.has(Attributes.Status.POISON):
		return
	#this effect only applies to hostile units
	if not unit.hostile:
		return
		
	var poison_stacks_applied: float = hit_data.status_effects[Attributes.Status.POISON].x
	if poison_stacks_applied <= 0:
		return

	# calculate the number of frost stacks to add
	var frost_stacks_to_add: float = poison_stacks_applied * 0.5
	
	# get the existing frost stacks on the hit, or default to 0
	var existing_frost_data: Vector2 = hit_data.status_effects.get(Attributes.Status.FROST, Vector2.ZERO)
	var existing_frost_stacks: float = existing_frost_data.x
	var existing_frost_duration: float = existing_frost_data.y # preserve original duration
	
	# add the new stacks and update the HitData object
	# because HitData is a RefCounted object, we are modifying the *actual* HitData
	# that the ModifiersComponent is about to process.
	hit_data.status_effects[Attributes.Status.FROST] = Vector2(
		existing_frost_stacks + frost_stacks_to_add,
		existing_frost_duration # you could also define a duration in the relic data
	)
