## SidebarUI.gd
#extends Control
#class_name SidebarUI
#
#@export var blueprint_bar: HBoxContainer
#@export var start_wave_button: Button
#@export var flux_display: Label
#
#
#func _ready() -> void:
	#_populate_blueprint_bar()
	#_update_flux(Player.flux)
	#
	#UI.update_blueprints.connect(func():
		#_populate_blueprint_bar()
	#)
	#UI.update_flux.connect(_update_flux)
	#UI.show_building_ui.connect(func():
		#start_wave_button.text = "start wave."
		#start_wave_button.disabled = false
	#)
	#UI.hide_building_ui.connect(func():
		#start_wave_button.text = "wave in progress."
		#start_wave_button.disabled = true
	#)
	#
	#start_wave_button.pressed.connect(func():
		#UI.building_phase_ended.emit()
	#)
#
#func _populate_blueprint_bar() -> void:
	#for child in blueprint_bar.get_children():
		#child.free()
#
	#for type_id: Towers.Type in Towers.Type.values():
		#var btn := Button.new()
		#btn.text = str(type_id).pad_zeros(2) + ": " + str(type_id)
		#btn.name = "Btn_%s" % str(type_id)
		#btn.pressed.connect(_on_button_pressed.bind(type_id))
		#blueprint_bar.add_child(btn)
#
#func _update_flux(flux: float):
	#flux_display.text = "flux: " + str(round(flux))
#
#func _on_button_pressed(type_id: Towers.Type) -> void:
	#UI.tower_selected.emit(type_id)

# SidebarUI.gd
extends Control
class_name SidebarUI

@export var blueprint_bar: HBoxContainer
@export var start_wave_button: Button
@export var flux_display: Label

func _ready() -> void:
	# Initial population and updates are handled by connecting to the signal.
	# Player.blueprints setter will emit the initial list.
	
	UI.update_blueprints.connect(_on_player_blueprints_updated)
	UI.update_flux.connect(_update_flux)
	
	UI.show_building_ui.connect(func():
		start_wave_button.text = "Start Wave" # More descriptive
		start_wave_button.disabled = false
	)
	UI.hide_building_ui.connect(func():
		start_wave_button.text = "Wave in Progress" # More descriptive
		start_wave_button.disabled = true
	)
	
	start_wave_button.pressed.connect(func():
		UI.building_phase_ended.emit()
	)

	# Request initial state if Player might have initialized before UI connected
	# (though with autoload order or call_deferred this might not be strictly necessary,
	# but good for robustness if Player's _ready completes and emits before UI's _ready connects)
	if Player and not Player.blueprints.is_empty():
		_on_player_blueprints_updated(Player.blueprints) # Manually call with current data
	else:
		_clear_blueprint_bar() # Ensure it's empty if no blueprints initially

	if Player:
		_update_flux(Player.flux)


func _clear_blueprint_bar() -> void:
	for child in blueprint_bar.get_children():
		blueprint_bar.remove_child(child) # Correct way to remove
		child.queue_free() # Then free it

# This function is now connected to UI.update_blueprints
func _on_player_blueprints_updated(current_player_bps: Array[Blueprint]) -> void:
	_clear_blueprint_bar()

	# Count how many of each blueprint type the player has
	var blueprint_counts: Dictionary = {} # Key: Towers.Type, Value: int (count)
	for bp: Blueprint in current_player_bps:
		if not blueprint_counts.has(bp.tower_type):
			blueprint_counts[bp.tower_type] = 0
		blueprint_counts[bp.tower_type] += 1

	# Create buttons for each tower type for which the player has at least one blueprint
	# Or, if you want to show all tower types and just display 0 if they don't have it:
	for tower_type_enum_value: Towers.Type in Towers.Type.values(): # Iterate all defined tower types
		var count: int = blueprint_counts.get(tower_type_enum_value, 0) # Get count, default to 0

		if count == 0:
			continue

		var btn := Button.new()
		var tower_name: String = str(tower_type_enum_value) # Get the string name of the enum value
		
		# Attempt to make the name a bit cleaner if it's like "TYPE_CANNON"
		tower_name = tower_name.replace("_", " ").capitalize()

		btn.text = "%s (%s)" % [tower_name, count]
		btn.name = "Btn_BP_%s" % str(tower_type_enum_value) # Use enum value for unique name
		
		# Disable button if player has no blueprints of this type
		if count == 0:
			btn.disabled = true
			# You might also want to style it differently (e.g., modulate color)
		else:
			btn.disabled = false
			# Only connect pressed if the button is active (player has blueprints)
			btn.pressed.connect(_on_blueprint_button_pressed.bind(tower_type_enum_value))
		
		blueprint_bar.add_child(btn)

func _update_flux(new_flux_value: float): 
	flux_display.text = "Flux: %s" % str(round(new_flux_value * 10) * 0.1) # Using string formatting

func _on_blueprint_button_pressed(type_id: Towers.Type) -> void:
	# This function is called when a blueprint button is pressed.
	# It emits a signal that ClickHandler (or another system) will listen to
	# to know which tower type the player intends to place next.
	UI.tower_selected.emit(type_id)
	print("SidebarUI: Blueprint button pressed for tower type: ", type_id)
