# breach_effect.gd
extends EffectPrototype
class_name BreachEffect
# --- parameters ---
# these are configured in the inspector for this effect resource.
@export var params: Dictionary = {
	"initial_waves_to_mature": 3,
	"initial_waves_to_live": 3,
}
# --- state ---
# this is the runtime state for each instance of the effect.
var state: Dictionary = {
	"waves_to_mature": 0,
	"waves_to_live": 0,
}

func _handle_attach(instance: EffectInstance) -> void:
	assert(instance.params.has("initial_waves_to_mature") and instance.params.has("initial_waves_to_live"))
	assert(instance.state.has("waves_to_mature" and instance.state.has("waves_to_live")))
	#initialise state variales
	instance.state.waves_to_mature = instance.params.initial_waves_to_mature
	instance.state.waves_to_live = instance.params.intiial_waves_to_live

# the main logic, triggered by game events.
func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	pass
