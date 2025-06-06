#Phases
extends Node

# Signals for UI interaction
signal display_expansion_choices(choices: Array[ExpansionChoice]) # UI listens to this
signal expansion_phase_ended # Waves node listens to this to resume
signal building_phase_started
signal building_phase_ended

# Ensure References.waves and References.island are correctly set up
# (e.g., in a global References.gd autoload script)

func _ready():
	Waves.offer_expansion_choices.connect(_on_waves_offer_expansion_choices) #entry point to expansion mechanism
	References.island.expansion_applied.connect(_on_island_expansion_applied) #reflects expansionchoices out to ui elements
	
	Waves.request_building_phase_start.connect(start_building_phase)
#EXPANSION PHASE
func _on_waves_offer_expansion_choices(choices: Array[ExpansionChoice]):
	print("Phases: Received expansion choices. Pausing waves and showing options.")
	assert(is_instance_valid(References.island))
	References.island.present_expansion_choices(choices) #entry point
	display_expansion_choices.emit(choices) # UI should connect to this signal

func player_chose_expansion(choice_id: int): 
	print("Phases: Player chose expansion: ", choice_id)
	assert(is_instance_valid(References.island))
	References.island.select_expansion(choice_id)

func _on_island_expansion_applied():
	print("Phases: Island expansion applied. Resuming waves.")
	expansion_phase_ended.emit() # Waves node connects to this to resume its timer
#BUILDING PHASE
func start_building_phase():
	print("Phases: Starting Building Phase.")
	building_phase_started.emit() # UI listens to this, shows "End Building Phase" button, etc.
	print("a")
	player_ended_building_phase()
# Called by your UI when the player clicks the "End Building Phase" button
func player_ended_building_phase():
	print("Phases: Player has ended the Building Phase. Emitting building_phase_ended.")
	building_phase_ended.emit() # Waves.gd listens to this
