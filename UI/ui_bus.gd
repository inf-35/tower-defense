extends Node #UI BUS (UI)
#all ui-logic communication should occur through this bus

#UI -> Phases
signal tower_selected(type_id: Towers.Type) #called by sidebar_ui
signal expansion_selected(expansion_id: int) #called by expansion_ui
signal building_phase_ended()
#Phases -> UI
signal display_expansion_choices(choices: Array[ExpansionChoice]) # To UI
signal hide_expansion_choices()
signal show_building_ui()
signal hide_building_ui()
