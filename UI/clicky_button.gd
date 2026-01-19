extends BaseButton
class_name ClickyButton

func _init() -> void:
	# connect this button's own built-in signals to its handler functions
	self.mouse_entered.connect(_clicky_on_mouse_entered)
	self.pressed.connect(_clicky_on_pressed)

# --- signal handlers ---

# called when the mouse enters the button's bounds
func _clicky_on_mouse_entered() -> void:
	# do not play a sound if the button is disabled
	if self.disabled:
		return
	
	# delegate the actual playing of the sound to the central AudioService
	Audio.play_sound(ID.Sounds.BUTTON_HOVER_SOUND, -5.0)
# called when the button is pressed
func _clicky_on_pressed() -> void:
	# the 'disabled' check is handled by the button itself, so we don't need it here
	
	Audio.play_sound(ID.Sounds.BUTTON_CLICK_SOUND, -1.0)
