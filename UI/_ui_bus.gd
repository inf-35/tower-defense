extends Node #UI BUS (UI)
#all ui-logic communication should occur through this bus

#UI -> Phases
signal tower_selected(type_id: Towers.Type) #called by sidebar_ui
signal expansion_selected(expansion_id: int) #called by expansion_ui
signal building_phase_ended() #called by sidebar_ui
#Phases -> UI
signal display_expansion_choices(choices: Array[ExpansionChoice]) # To UI
signal hide_expansion_choices()
signal show_building_ui()
signal hide_building_ui()
#multiple sources -> Inspector
signal update_unit_state(unit : Unit)
#Player -> UI
signal update_blueprints(blueprints: Array[Blueprint])
signal update_flux(flux: float)
#Handler/Sidebar -> Inspector
signal update_inspector_bar(tower: Tower)
