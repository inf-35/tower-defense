extends Node #UI BUS (UI)
#all ui-logic communication should occur through this bus
@warning_ignore_start("unused_signal")
signal tower_dying(tower: Tower) #called by towers before death
#UI -> clock
signal gamespeed_toggled(speed: Clock.GameSpeed)
#UI -> Phases
signal tower_selected(tower: Tower) #called by sidebar_ui
signal tower_option_selected(tower_type: Towers.Type)
signal choice_hovered(choice_id: int) #generic choice ui handlers
signal choice_unhovered(choice_id: int)
signal choice_focused(choice_id: int) #used by expansion_ui
signal choice_selected(choice_id: int) #called by expansion_ui and reward_ui
signal expansion_finished() #called by expansion_ui
signal reward_rerolled() #called by reward_ui
signal building_phase_ended() #called by sidebar_ui
#ClickHandler/UI -> Player
signal place_tower_requested(tower_type: Towers.Type, position: Vector2i, facing: Tower.Facing)
signal sell_tower_requested(tower: Tower)
signal excavate_rite_requested(tower: Tower)
signal upgrade_tower_requested(tower: Tower, upgrade_type: Towers.Type)
#Trader
signal trader_open()
signal trader_close()
signal trader_update_restock_cost(restock_cost: float)
signal trader_update_stock(current_stock: Array[Reward])
signal trader_update_waves_to_next_restock(waves: int)
signal trader_unseen_stock_changed(has_unseen_stock: bool)
signal trader_choice_selected(choice_id: int) ##called by trader ui
signal trader_force_restock_requested() ##..
#Phases -> UI
signal update_wave_schedule()
signal start_wave(wave : int)
signal end_wave(wave: int)
signal start_phase(wave: int, combat: bool, subtype: int)
signal day_event_ended() ##when any day event, including NONE, ends.
signal start_combat(wave: int)
signal display_expansion_choices(choices: Array[ExpansionChoice]) #to ui
signal hide_expansion_choices()
signal display_expansion_confirmation(pending_choice_id: int)
signal hide_expansion_confirmation()
signal display_expansion_exit()
signal hide_expansion_exit()
signal display_reward_choices(choices: Array[Reward])
signal update_reroll_cost(reroll_cost: float) #from rewardservice
signal hide_reward_choices()
signal show_building_ui()
signal hide_building_ui()
signal display_game_over(is_victory: bool)
#multiple sources -> Inspector
signal update_unit_state(unit : Unit)
signal update_unit_health(unit : Unit, max_hp : float, hp : float)
signal boss_encounter_started(title: String, boss_unit: Unit)
signal boss_health_changed(max_hp: float, hp: float)
signal boss_subwave_changed(subwave_index: int)
signal boss_encounter_ended()
#Inspector -> unit
signal get_unit_state(unit: Unit)
#Player -> UI
#signal update_blueprints(blueprints: Array[Blueprint]) #WARNING: DEPRECATED
signal update_tower_types(unlocked_tower_types : Dictionary[Towers.Type, bool], flux_inventory: Dictionary[Towers.Type, int])
signal update_tower_counts()
signal update_flux(flux: float)
signal update_capacity(used: float, total: float)
signal update_health(health: float)
signal update_relics()
signal update_damage_tracker(entries: Array[Dictionary], max_damage: float)
signal reset_damage_tracker(wave_number: int)
#Handler/Sidebar -> Inspector
signal update_inspector_bar(unit: Unit)

var _player_ui_update_queued: bool = false
var _has_pending_flux_update: bool = false
var _has_pending_capacity_update: bool = false
var _has_pending_health_update: bool = false
var _has_pending_tower_types_update: bool = false
var _has_pending_relics_update: bool = false
var _pending_flux: float = 0.0
var _pending_capacity_used: float = 0.0
var _pending_capacity_total: float = 0.0
var _pending_health: float = 0.0
var _pending_unlocked_tower_types: Dictionary[Towers.Type, bool] = {}
var _pending_rite_inventory: Dictionary[Towers.Type, int] = {}

static var tutorial_manager: TutorialManager
static var cursor_info: CursorInfo
static var floating_text_manager: FloatingTextManager
static var world_unit_ui_manager: WorldUnitUIManager
static var loading_screen: LoadingScreen
static var reward_pickup_animator: RewardPickupAnimator

func queue_update_flux(flux: float) -> void: ##coalesces player flux ui updates so combat rewards only wake listeners once per frame
	_pending_flux = flux
	_has_pending_flux_update = true
	_queue_player_ui_update_flush()

func queue_update_capacity(used: float, total: float) -> void: ##coalesces player capacity ui updates around build/sell bursts
	_pending_capacity_used = used
	_pending_capacity_total = total
	_has_pending_capacity_update = true
	_queue_player_ui_update_flush()

func queue_update_health(health: float) -> void: ##coalesces player health ui updates while preserving the latest visible value
	_pending_health = health
	_has_pending_health_update = true
	_queue_player_ui_update_flush()

func queue_update_tower_types(unlocked_tower_types: Dictionary[Towers.Type, bool], rite_inventory: Dictionary[Towers.Type, int]) -> void: ##coalesces tower palette refreshes and keeps only the newest player loadout
	_pending_unlocked_tower_types = unlocked_tower_types
	_pending_rite_inventory = rite_inventory
	_has_pending_tower_types_update = true
	_queue_player_ui_update_flush()

func queue_update_relics() -> void: ##coalesces relic display rebuild requests that can arrive with the same economy mutation
	_has_pending_relics_update = true
	_queue_player_ui_update_flush()

func _queue_player_ui_update_flush() -> void: ##schedules one deferred player-ui flush no matter how many player state signals fire this frame
	if _player_ui_update_queued:
		return
	_player_ui_update_queued = true
	call_deferred("_flush_player_ui_updates")

func _flush_player_ui_updates() -> void: ##emits each queued player-ui signal at most once with the newest value seen this frame
	_player_ui_update_queued = false
	if not Run.has_active_run() or not is_instance_valid(Run.player):
		_clear_pending_player_ui_updates()
		return

	if _has_pending_flux_update:
		_has_pending_flux_update = false
		update_flux.emit(_pending_flux)

	if _has_pending_capacity_update:
		_has_pending_capacity_update = false
		update_capacity.emit(_pending_capacity_used, _pending_capacity_total)

	if _has_pending_health_update:
		_has_pending_health_update = false
		update_health.emit(_pending_health)

	if _has_pending_tower_types_update:
		_has_pending_tower_types_update = false
		update_tower_types.emit(_pending_unlocked_tower_types, _pending_rite_inventory)

	if _has_pending_relics_update:
		_has_pending_relics_update = false
		update_relics.emit()

func _clear_pending_player_ui_updates() -> void: ##drops stale deferred player-ui updates after the run state has been torn down
	_has_pending_flux_update = false
	_has_pending_capacity_update = false
	_has_pending_health_update = false
	_has_pending_tower_types_update = false
	_has_pending_relics_update = false
	_pending_unlocked_tower_types.clear()
	_pending_rite_inventory.clear()
