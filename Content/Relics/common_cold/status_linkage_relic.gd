# ruined_ground_slow_effect.gd
extends GlobalEffect
class_name StatusLinkageRelic

# --- configuration (designer-friendly) ---
@export var input_status: Attributes.Status
@export var output_status: Attributes.Status
@export var conversion: float = 0.0

func initialise() -> void:
	Player.on_event.connect(_on_event)

func _on_event(_unit: Unit, game_event: GameEvent):
	if game_event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
	
	var hit_data: HitData = game_event.data as HitData
	if hit_data.status_effects.has(input_status):
		var input_status_vector: Vector2 = hit_data.status_effects[input_status]
		var output_status_vector: Vector2 = Vector2(input_status_vector.x * conversion, input_status_vector.y)
		#add output status to the hitdata
		var existing_output_status_vector: Vector2 = hit_data.status_effects[output_status] if hit_data.status_effects.has(output_status) else Vector2.ZERO
		hit_data.status_effects[output_status] = Vector2(output_status_vector.x + existing_output_status_vector.x, maxf(output_status_vector.y, existing_output_status_vector.y))
		#we add stacks, and take the maximum of duratons
