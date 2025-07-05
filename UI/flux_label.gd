extends Label
class_name FluxLabel

func _ready() -> void:
	UI.update_flux.connect(_update_flux)
	
	if Player:
		_update_flux(Player.flux)
	
func _update_flux(new_flux_value: float): 
	text = "Flux: %s" % str(round(new_flux_value * 10) * 0.1) # Using string formatting
