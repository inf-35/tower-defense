extends InteractiveRichTextLabel
class_name FluxLabel

func _ready() -> void:
	UI.update_flux.connect(_update_flux)
	
	if Player:
		_update_flux(Player.flux)
	
func _update_flux(new_flux_value: float): 
	set_parsed_text("{FLUX}: %s" % str(round(new_flux_value * 10) * 0.1)) # Using string formatting
	print(text)
