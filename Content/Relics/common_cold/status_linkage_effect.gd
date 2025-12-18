extends EffectPrototype
class_name StatusLinkageEffect

# --- configuration ---
@export var input_status: Attributes.Status
@export var output_status: Attributes.Status
@export var conversion_rate: float = 0.5 ## percentage of stacks to transfer (e.g. 0.5 = 50%)

func _init() -> void:
	# we hook into hit_received to modify the hit data before the unit processes it
	global = true
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	# no persistent state needed
	return instance

# --- logic handlers ---
func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	# access the hit data that is currently travelling through the event bus
	var hit_data := event.data as HitData
	
	# check if the trigger condition is met
	if not hit_data or not hit_data.status_effects.has(input_status):
		return
		
	# retrieve input data (x = stacks, y = duration)
	var input_vector: Vector2 = hit_data.status_effects[input_status]
	
	# calculate the new stacks to add based on conversion rate
	var generated_stacks: float = input_vector.x * conversion_rate
	var generated_duration: float = input_vector.y # duration matches the trigger status
	
	# check if the hit already has the output status to merge values
	var existing_vector: Vector2 = Vector2.ZERO
	if hit_data.status_effects.has(output_status):
		existing_vector = hit_data.status_effects[output_status]
	
	# merge logic: add stacks, take the longest duration
	var final_stacks: float = existing_vector.x + generated_stacks
	var final_duration: float = maxf(existing_vector.y, generated_duration)
	
	# write back to the hit data
	hit_data.status_effects[output_status] = Vector2(final_stacks, final_duration)
