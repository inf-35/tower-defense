#player.gd
#this script can be seen as the "agent" of the player interacting with game logic and ui
extends Node
class_name Player

signal flux_changed(new_flux: float)
signal hp_changed(new_health: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary[Towers.Type, bool])
signal relics_changed()
signal relic_slots_changed()
signal tower_placed(tower_type: Towers.Type, tower: Tower) ##fires only after a tower placement request succeeds and the runtime tower exists
signal rite_excavated(tower: Tower) ##fires after a rite is successfully returned to inventory through excavation

signal on_event(unit: Unit, game_event: GameEvent) ##global event signal bus, collects events from all units
#and relevant towers

const DEBUG_REMOVE_RELIC_ACTION: StringName = &"debug_remove_relic"

const DEBUG_CAPACITY: bool = false
const RITE_EXCAVATION_COST: float = 3.0
const BASE_RELIC_SLOTS: int = 4
const RELIC_SLOT_FIRST_COST: float = 8.0
const RELIC_SLOT_COST_SCALE: float = 1.8

#inclusion in Player is merited by their clear player-side nature.
#various player-side states.
var flux: float = 200.0:
	set(value):
		flux = value
		flux_changed.emit(flux)

var hp: float:
	set(value):
		hp = value
		hp_changed.emit(hp)
		if hp < 0.0 or is_zero_approx(hp):
			if not Run.phases.is_game_over:
				Run.phases.start_game_over(false)

var used_capacity: float = 0.0:
	set(value):
		used_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)

var tower_capacity: float = 0.0:
	set(value):
		tower_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)

var unlocked_towers: Dictionary[Towers.Type, bool] = {}:
	set(value):
		unlocked_towers = value
		unlocked_towers_changed.emit(unlocked_towers, rite_inventory)

var _tower_limits: Dictionary[Towers.Type, int] = {} ##stores placement limits of various towers, by default -1, which is infinite

var rite_inventory: Dictionary[Towers.Type, int] = {}

var active_relics: Array[RelicData]
var _active_relic_effects: Dictionary[RelicData, EffectInstance] = {}
var relic_slot_capacity: int = BASE_RELIC_SLOTS:
	set(value):
		relic_slot_capacity = maxi(value, BASE_RELIC_SLOTS)
		relic_slots_changed.emit()

#tutorial
enum TutorialFlag {
	MAIN,
	PAUSE,
	TROLL,
	TOWER_DESTROYED,
	RUINS,
	RITE,
	ONBOARDING,
	SHOP,
}

var completed_tutorials: Dictionary[TutorialFlag, bool] = {
	TutorialFlag.MAIN: false,
	TutorialFlag.PAUSE: false,
	TutorialFlag.TROLL: false,
	TutorialFlag.TOWER_DESTROYED: false,
	TutorialFlag.RUINS: false,
	TutorialFlag.RITE: false,
	TutorialFlag.ONBOARDING: false,
	TutorialFlag.SHOP: false,
}

#various services (which are children of this node)
var ruin_service: RuinService
var global_event_service: GlobalEventService
var trader_service: TraderService

func _ready() -> void:
	#connect to UI player input signals
	UI.place_tower_requested.connect(_on_place_tower_requested)
	UI.sell_tower_requested.connect(_on_sell_tower_requested)
	UI.excavate_rite_requested.connect(_on_excavate_rite_requested)
	UI.upgrade_tower_requested.connect(_on_upgrade_tower_requested)
	UI.reward_rerolled.connect(_on_reward_reroll_requested)
	#couple playerside logic signals with UI output signals
	flux_changed.connect(UI.update_flux.emit)
	capacity_changed.connect(UI.update_capacity.emit)
	hp_changed.connect(UI.update_health.emit)
	unlocked_towers_changed.connect(UI.update_tower_types.emit)
	relics_changed.connect(UI.update_relics.emit)
	relic_slots_changed.connect(UI.update_relics.emit)
	#Run.phases.wave_ended.connect(func(_wave):
		#Run.player.flux += 6
	#)

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(DEBUG_REMOVE_RELIC_ACTION):
		return
	if event is InputEventKey and event.echo:
		return
	if active_relics.is_empty():
		return

	get_viewport().set_input_as_handled()
	remove_relic(active_relics[0])

func start() -> void:
	for relic: RelicData in active_relics.duplicate():
		remove_relic(relic)

	for unit: Unit in get_tree().get_nodes_in_group(Run.references.TOWER_GROUP):
		unit.queue_free()

	for unit: Unit in get_tree().get_nodes_in_group(Run.waves.ENEMY_GROUP):
		unit.queue_free()

	rite_inventory.clear()
	_tower_limits.clear()
	unlocked_towers.clear()
	active_relics.clear()
	_active_relic_effects.clear()
	relic_slot_capacity = BASE_RELIC_SLOTS

	tower_capacity = 0.0
	used_capacity = 0.0

	if global_event_service: global_event_service.free()
	if ruin_service: ruin_service.free()

	#setup event bus
	global_event_service = GlobalEventService.new()
	add_child(global_event_service)
	global_event_service.initialise_event_bus(on_event)

	#create and setup services
	ruin_service = RuinService.new()
	add_child(ruin_service)
	ruin_service.initialise()

	trader_service = TraderService.new()
	add_child(trader_service)
	trader_service.initialise()

	#
	#var reward := Reward.new()
	#reward.type = Reward.Type.ADD_RITE
	#reward.rite_type = Towers.Type.RITE_F
	#
	#RewardService.apply_reward(reward)


func begin_new_game() -> void:
	#initial state setup
	self.unlocked_towers = {
		Towers.Type.TURRET: true,
		Towers.Type.PALISADE: true,
		Towers.Type.FARM: true,
		Towers.Type.GENERATOR: true,
		#Towers.Type.SNOWBALL: true,
	}
	
	#var reward := Reward.new()
	##reward.type = Reward.Type.ADD_RITE
	##reward.rite_type = Towers.Type.RITE_POISONS
	##RewardService.apply_reward(reward)
	###reward.rite_type = Towers.Type.RITE_FROST
	###RewardService.apply_reward(reward)
	#reward.type = Reward.Type.ADD_RELIC
	#reward.relic = Relics.EDELWEISS
	#RewardService.apply_reward(reward)
	###reward.relic = preload("res://Content/Relics/sapphire_idol/sapphire_idol.tres")
	###RewardService.apply_reward(reward)
	###reward.relic = Relics.ALCHEMISTS_STONE
	###RewardService.apply_reward(reward)
	#reward.relic = Relics.SPRINKLERHEAD
	#RewardService.apply_reward(reward)
	#reward.relic = Relics.EPIDEMIC
	#RewardService.apply_reward(reward)
	##reward.relic = Relics.RUPTURED_HEART
	##RewardService.apply_reward(reward)


	flux = 30.0
	hp = 20.0

	trader_service.start_game()

	UI.update_flux.emit(flux)
	UI.update_health.emit(hp)
	UI.update_relics.emit()
	UI.update_tower_types.emit(unlocked_towers, rite_inventory)

#capacity helper functions
func _debug_capacity(channel: String, delta: float, reason: String = "") -> void:
	if not DEBUG_CAPACITY:
		return
	var suffix := "" if reason.is_empty() else " | " + reason
	print("[Capacity][%s] delta=%s | used=%s | total=%s%s" % [
		channel,
		str(delta),
		str(used_capacity),
		str(tower_capacity),
		suffix,
	])

func add_to_used_capacity(amount: float, reason: String = "") -> void:
	self.used_capacity += amount
	_debug_capacity("used", amount, reason)

func remove_from_used_capacity(amount: float, reason: String = "") -> void:
	self.used_capacity -= amount
	_debug_capacity("used", -amount, reason)

func add_to_total_capacity(amount : float, reason: String = "") -> void:
	self.tower_capacity += amount
	_debug_capacity("total", amount, reason)

func remove_from_total_capacity(amount : float, reason: String = "") -> void:
	self.tower_capacity -= amount
	_debug_capacity("total", -amount, reason)

func has_capacity(tower_type : Towers.Type) -> bool:
	return Run.player.used_capacity + Towers.get_tower_capacity(tower_type) - 0.01 < Run.player.tower_capacity

#tower unlock helper functions
func unlock_tower(tower_type : Towers.Type, unlock : bool = true) -> void:
	unlocked_towers[tower_type] = unlock
	unlocked_towers_changed.emit(unlocked_towers, rite_inventory)

func is_tower_unlocked(tower_type : Towers.Type) -> bool:
	return unlocked_towers.get(tower_type, false)

func add_to_tower_limit(type: Towers.Type, amount: int) -> void:
	var current: int = _tower_limits.get(type, 0)
	_tower_limits[type] = current + amount
	#TODO: implement UI updates

func get_tower_limit(type: Towers.Type) -> int:
	return _tower_limits.get(type, -1)

func add_rite(type: Towers.Type, amount: int) -> void:
	var current: int = rite_inventory.get(type, 0)
	rite_inventory[type] = maxi(current + amount, 0)

	if rite_inventory[type] > 0:
		unlocked_towers[type] = true
	else:
		unlocked_towers.erase(type)

	unlocked_towers_changed.emit(unlocked_towers, rite_inventory)

func get_rite_count(type: Towers.Type) -> int: ##number of rites left
	return rite_inventory.get(type, 0)

#relic entry point (to add new relics)
func add_relic(relic: RelicData) -> void:
	if not is_instance_valid(relic):
		return
	if _has_relic_resource(relic):
		return
	if not can_add_relic(relic):
		return

	active_relics.append(relic)

	if relic.global_effect:
		_active_relic_effects[relic] = global_event_service.register_effect(relic.global_effect)

	#announce that the global state has changed
	relics_changed.emit()

func remove_relic(relic: RelicData) -> bool:
	if not is_instance_valid(relic):
		return false

	var matched_relic: RelicData = _find_active_relic_resource(relic)
	if not is_instance_valid(matched_relic):
		return false

	if _active_relic_effects.has(matched_relic):
		global_event_service.deregister_effect(_active_relic_effects[matched_relic])
		_active_relic_effects.erase(matched_relic)

	active_relics.erase(matched_relic)
	relics_changed.emit()
	return true

func remove_relic_by_type(relic_type: RelicData.Type) -> bool:
	for relic: RelicData in active_relics:
		if is_instance_valid(relic) and relic.type == relic_type:
			return remove_relic(relic)
	return false

func has_free_relic_slot() -> bool: ##returns whether the player currently has at least one unoccupied relic slot
	return active_relics.size() < relic_slot_capacity

func can_add_relic(relic: RelicData) -> bool: ##checks both duplicate ownership and capacity before allowing one more relic
	if not is_instance_valid(relic):
		return false
	if _has_relic_resource(relic):
		return false
	return has_free_relic_slot()

func get_next_relic_slot_cost() -> float: ##derives the next slot purchase cost from current capacity so persistence falls out automatically
	var purchase_index: int = maxi(relic_slot_capacity - BASE_RELIC_SLOTS, 0)
	var cost: float = RELIC_SLOT_FIRST_COST
	for _index: int in range(purchase_index):
		cost = ceil(cost * RELIC_SLOT_COST_SCALE)
	return cost

func try_purchase_relic_slot() -> bool: ##attempts to buy one more relic slot directly from the player's gold pool
	var cost: float = get_next_relic_slot_cost()
	if flux < cost:
		return false
	flux -= cost
	relic_slot_capacity += 1
	relics_changed.emit()
	return true

func get_relic_effect_instance(relic: RelicData) -> EffectInstance:
	var matched_relic: RelicData = _find_active_relic_resource(relic)
	if not is_instance_valid(matched_relic):
		return null
	return _active_relic_effects.get(matched_relic, null) as EffectInstance

func _has_relic_resource(relic: RelicData) -> bool:
	return is_instance_valid(_find_active_relic_resource(relic))

func _find_active_relic_resource(relic: RelicData) -> RelicData:
	if not is_instance_valid(relic):
		return null
	for active_relic: RelicData in active_relics:
		if active_relic == relic:
			return active_relic
		if is_instance_valid(active_relic) and active_relic.type == relic.type:
			return active_relic
	return null

#this is the core query function used by modifierscomponent
func get_modifiers_for_unit(unit: Unit) -> Array[Modifier]:
	var relevant_modifiers: Array[Modifier] = []

	for relic: RelicData in active_relics:
		#check if the unit matches the relic's targeting rules
		for modifier_prototype: GlobalModifierPrototype in relic.modifier_prototypes:
			if not modifier_prototype.matches_unit(unit):
				continue
			var new_modifier: Modifier = modifier_prototype.generate_modifier()
			#brand it with a source id for debugging, if needed
			new_modifier.source_id = -1 #use a special id for global mods
			relevant_modifiers.append(new_modifier)

	return relevant_modifiers

func _on_place_tower_requested(tower_type: Towers.Type, cell: Vector2i, facing: Tower.Facing) -> void:
	#NOTE: reduplicated logic from TerrainService (condense?)
	if not unlocked_towers.get(tower_type, false):
		return

	if flux < Towers.get_tower_cost(tower_type):
		return

	if not (tower_type == Towers.Type.GENERATOR and Run.references.island.get_terrain_base(cell) == Terrain.Base.SETTLEMENT):
		if used_capacity + Towers.get_tower_capacity(tower_type) > tower_capacity and not is_zero_approx(Towers.get_tower_capacity(tower_type)):
			#note: you could add a ui warning here about insufficient capacity.
			return
	var attempted_cost: float = Towers.get_tower_cost(tower_type)
	self.flux -= attempted_cost
	var success = Run.references.island.request_tower_placement(cell, tower_type, facing)

	#3. if the island confirms placement, deduct resources.
	if success:
		Audio.play_sound(ID.Sounds.TOWER_PLACED_SOUND, 0.0, Island.cell_to_position(cell))
		var placed_tower: Tower = Run.references.island.get_tower_on_tile(cell)
		if is_instance_valid(placed_tower):
			tower_placed.emit(tower_type, placed_tower)

		if Towers.is_tower_rite(tower_type):
			self.add_rite(tower_type, -1)
	else:
		self.flux += attempted_cost

func _on_sell_tower_requested(tower) -> void:
	if not is_instance_valid(tower):
		return
	if tower is Tower:
		tower.sell()

func _on_excavate_rite_requested(tower) -> void:
	if not is_instance_valid(tower):
		return
	assert(tower is Tower and Towers.is_tower_rite(tower.type), "Excavation expects a rite tower.")
	if tower.current_state != Tower.State.ACTIVE:
		return
	if flux < RITE_EXCAVATION_COST:
		return

	self.flux -= RITE_EXCAVATION_COST
	add_rite(tower.type, 1)
	rite_excavated.emit(tower)
	tower.excavate()

func _on_upgrade_tower_requested(old_tower: Tower, upgrade_type: Towers.Type) -> void:
	var cost: float = Towers.get_tower_upgrade_cost(old_tower.type, upgrade_type)
	if self.flux < cost:
		return

	var success: bool = Run.references.island.request_upgrade(old_tower, upgrade_type)

	if success:
		self.flux -= cost

func _on_reward_reroll_requested() -> void:
	var cost: float = RewardService.get_reroll_cost()
	if self.flux < cost:
		return
	self.flux -= cost
	RewardService.reroll()

func get_save_data() -> Dictionary:
	var save_data: Dictionary = {
		"gold": flux,
		"hp": hp,
		"unlocked_towers": unlocked_towers,
		"rite_inventory": rite_inventory,
		"relic_slot_capacity": relic_slot_capacity,
	}

	var relics_data: Array[Dictionary] = []
	for active_relic: RelicData in active_relics:
		relics_data.append(active_relic.get_save_data()) #see this for relic/effect serialisation

	save_data["relics"] = relics_data
	save_data["trader"] = trader_service.get_save_data()
	return save_data

func load_save_data(save_data: Dictionary) -> void:
	flux = float(save_data.gold)
	hp = int(save_data.hp)
	relic_slot_capacity = int(save_data.get("relic_slot_capacity", BASE_RELIC_SLOTS))

	for unlocked_tower_type in save_data.unlocked_towers:
		unlocked_towers[int(unlocked_tower_type)] = bool(save_data.unlocked_towers[unlocked_tower_type])
	for unlocked_rite_type in save_data.rite_inventory:
		rite_inventory[int(unlocked_rite_type)] = int(save_data.rite_inventory[unlocked_rite_type])
	#readd relics in the sequence in which they were originally added
	for active_relic: Dictionary in save_data.relics:
		load_relic(active_relic)

	if save_data.has("trader"):
		trader_service.load_save_data(save_data.trader)

	UI.update_relics.emit()
	UI.update_flux.emit(flux)
	UI.update_health.emit(hp)
	UI.update_tower_types.emit(unlocked_towers, rite_inventory)

func load_relic(active_relic: Dictionary) -> void: #add_relic, but for loading
	var relic: RelicData = load(active_relic.resource_path) as RelicData
	if not is_instance_valid(relic):
		return
	add_relic(relic)
	var effect_instance: EffectInstance = get_relic_effect_instance(relic)
	if is_instance_valid(effect_instance) and active_relic.has("global_effect"):
		effect_instance.effect_prototype.load_save_data(effect_instance, active_relic.global_effect)

func get_profile() -> Dictionary:
	var profile_data: Dictionary = {
		"completed_tutorials": completed_tutorials,
	}
	return profile_data

func load_profile(profile_data: Dictionary) -> void:
	var saved_tutorials: Dictionary = profile_data.get("completed_tutorials", {})
	for tutorial_key: String in saved_tutorials:
		completed_tutorials[int(tutorial_key)] = saved_tutorials[tutorial_key]
	if not saved_tutorials.has(str(TutorialFlag.ONBOARDING)) and not saved_tutorials.has(TutorialFlag.ONBOARDING):
		completed_tutorials[TutorialFlag.ONBOARDING] = completed_tutorials[TutorialFlag.MAIN] and completed_tutorials[TutorialFlag.PAUSE] and completed_tutorials[TutorialFlag.RITE]
