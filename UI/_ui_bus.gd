extends Node #UI BUS (UI)
#all ui-logic communication should occur through this bus
@warning_ignore_start("unused_signal")
signal tower_dying(tower: Tower) #called by towers before death
#UI -> clock
signal gamespeed_toggled(speed: Clock.GameSpeed)
#UI -> Phases
signal tower_selected(tower: Tower) #called by sidebar_ui
signal choice_hovered(choice_id: int) #generic choice ui handlers
signal choice_unhovered(choice_id: int)
signal choice_focused(choice_id: int) #used by expansion_ui
signal choice_selected(choice_id: int) #called by expansion_ui and reward_ui
signal building_phase_ended() #called by sidebar_ui
#ClickHandler/UI -> Player
signal place_tower_requested(tower_type: Towers.Type, position: Vector2i, facing: Tower.Facing)
signal sell_tower_requested(tower: Tower)
signal upgrade_tower_requested(tower: Tower, upgrade_type: Towers.Type)
#Phases -> UI
signal update_wave_schedule()
signal start_wave(wave : int)
signal end_wave(wave: int)
signal day_event_ended() ##when any day event, including NONE, ends.
signal start_combat(wave: int)
signal display_expansion_choices(choices: Array[ExpansionChoice]) # To UI
signal hide_expansion_choices()
signal display_expansion_confirmation(pending_choice_id: int)
signal hide_expansion_confirmation()
signal display_reward_choices(choices: Array[Reward]) #the frontend isnt actually done yet
signal hide_reward_choices()
signal show_building_ui()
signal hide_building_ui()
signal display_game_over(is_victory: bool)
#multiple sources -> Inspector
signal update_unit_state(unit : Unit)
signal update_unit_health(unit : Unit, max_hp : float, hp : float)
#Inspector -> unit
signal get_unit_state(unit: Unit)
#Player -> UI
#signal update_blueprints(blueprints: Array[Blueprint]) #WARNING: DEPRECATED
signal update_tower_types(unlocked_tower_types : Dictionary[Towers.Type, bool], flux_inventory: Dictionary[Towers.Type, int])
signal update_flux(flux: float)
signal update_capacity(used: float, total: float)
signal update_health(health: float)
signal update_relics()
#Handler/Sidebar -> Inspector
signal update_inspector_bar(tower: Tower)

static var tutorial_manager: TutorialManager
static var cursor_info: CursorInfo
