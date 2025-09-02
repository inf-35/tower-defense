extends Node #UI BUS (UI)
#all ui-logic communication should occur through this bus

signal tower_dying(tower: Tower) #called by towers before death
#UI -> Phases
signal tower_selected(type_id: Towers.Type) #called by sidebar_ui
signal choice_hovered(choice_id: int)
signal choice_unhovered(choice_id: int)
signal choice_selected(choice_id: int) #called by expansion_ui
signal building_phase_ended() #called by sidebar_ui
#ClickHandler/UI -> Player
signal place_tower_requested(tower_type: Towers.Type, position: Vector2i, facing: Tower.Facing)
signal sell_tower_requested(tower: Tower)
#Phases -> UI
signal update_wave_schedule()
signal start_wave(wave : int)
signal display_expansion_choices(choices: Array[ExpansionChoice]) # To UI
signal hide_expansion_choices()
signal display_reward_choices() #the frontend isnt actually done yet
signal hide_reward_choices()
signal show_building_ui()
signal hide_building_ui()
#multiple sources -> Inspector
signal update_unit_state(unit : Unit)
signal update_unit_health(unit : Unit, max_hp : float, hp : float)
#Player -> UI
#signal update_blueprints(blueprints: Array[Blueprint]) #WARNING: DEPRECATED
signal update_tower_types(unlocked_tower_types : Dictionary[Towers.Type, bool])
signal update_flux(flux: float)
signal update_capacity(used: float, total: float)
#Handler/Sidebar -> Inspector
signal update_inspector_bar(tower: Tower)
