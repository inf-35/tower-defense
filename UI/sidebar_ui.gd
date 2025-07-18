extends Control
class_name SidebarUI

@export var towers_bar: VBoxContainer
@export var start_wave_button: Button

func _ready() -> void:
	# Initial population and updates are handled by connecting to the signal.
	# Player.towerss setter will emit the initial list.
	
	UI.update_tower_types.connect(_on_player_tower_types_update)
	
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
	if Player:
		_on_player_tower_types_update(Player.unlocked_towers)
	else:
		_clear_towers_bar() # Ensure it's empty if no towerss initially


func _clear_towers_bar() -> void:
	for child in towers_bar.get_children():
		towers_bar.remove_child(child) # Correct way to remove
		child.queue_free() # Then free it

func _on_player_tower_types_update(unlocked_tower_types : Dictionary[Towers.Type, bool]) -> void:
	_clear_towers_bar()
	
	var tower_types_by_id : Array[Towers.Type] = unlocked_tower_types.keys()
	tower_types_by_id.sort()
	
	for unlocked_tower_type : Towers.Type in tower_types_by_id:
		if not unlocked_tower_types[unlocked_tower_type]:
			continue
			
		var btn := Button.new()
		var tower_name : String = str(Towers.Type.keys()[unlocked_tower_type]) #TODO: implement localisation
		tower_name = tower_name.replace("_", " ").capitalize()
		
		btn.text = tower_name
		btn.name = "button_%s" % tower_name
		
		btn.pressed.connect(_on_tower_button_pressed.bind(unlocked_tower_type))
		towers_bar.add_child(btn)
	
func _on_tower_button_pressed(type_id: Towers.Type) -> void:
	# This function is called when a towers button is pressed.
	# It emits a signal that ClickHandler (or another system) will listen to
	# to know which tower type the player intends to place next.
	UI.tower_selected.emit(type_id)
	UI.update_inspector_bar.emit(Towers.get_tower_prototype(type_id)) #update inspector bar to fit whatever we're selecting
