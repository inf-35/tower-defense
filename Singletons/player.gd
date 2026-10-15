#player.gd
#this script can be seen as the "agent" of the player interacting with game logic and ui
extends Node
class_name Player

signal flux_changed(new_flux: float)
signal hp_changed(new_health: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary[Towers.Type, bool], rite_inventory: Dictionary[Towers.Type, int])
signal relics_changed()
signal relic_slots_changed()
signal tower_placed(tower_type: Towers.Type, tower: Tower) ##fires only after a tower placement request succeeds and the runtime tower exists
signal rite_excavated(tower: Tower) ##fires after a rite is successfully returned to inventory through excavation

const DEBUG_REMOVE_RELIC_ACTION: StringName = &"debug_remove_relic"

const DEBUG_CAPACITY: bool = false
const RITE_EXCAVATION_COST: float = 0.0
const BASE_RELIC_SLOTS: int = 4
const RELIC_SLOT_FIRST_COST: float = 8.0
const RELIC_SLOT_COST_SCALE: float = 1.8
const MAX_ACTIVE_TOWER_TYPES: int = 999
const DEBUG_GRANT_TEST_CONTENT: bool = false
const DEBUG_TEST_FLUX: float = 200.0

#inclusion in Player is merited by their clear player-side nature.
#various player-side states.
var flux: float = 200.0:
	set(value):
		flux = value
		flux_changed.emit(flux)

var hp: float:
	set(value):
		var health_loss: PlayerHealthLossData = null
		if value < hp:
			health_loss = PlayerHealthLossData.new()
			health_loss.health_before = hp
			health_loss.health_after = value
			var event := GameEvent.new()
			event.event_type = GameEvent.EventType.PLAYER_HEALTH_LOSS
			event.data = health_loss
			publish_event(null, event)
			value = health_loss.health_after

		hp = value
		hp_changed.emit(hp)
		if health_loss != null:
			health_loss.resolved.emit()
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
	TROLL = 2,
	TOWER_DESTROYED = 3,
	RUINS = 4,
	RITE = 5,
	ONBOARDING = 6,
	SHOP = 7,
}

var completed_tutorials: Dictionary[TutorialFlag, bool] = {
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
	_ensure_global_event_service()
	#connect to UI player input signals
	UI.place_tower_requested.connect(_on_place_tower_requested)
	UI.sell_tower_requested.connect(_on_sell_tower_requested)
	UI.excavate_rite_requested.connect(_on_excavate_rite_requested)
	UI.upgrade_tower_requested.connect(_on_upgrade_tower_requested)
	UI.reward_rerolled.connect(_on_reward_reroll_requested)
	#couple playerside logic signals with UI output signals
	flux_changed.connect(UI.queue_update_flux)
	capacity_changed.connect(UI.queue_update_capacity)
	hp_changed.connect(UI.queue_update_health)
	unlocked_towers_changed.connect(UI.queue_update_tower_types)
	relics_changed.connect(UI.queue_update_relics)
	relic_slots_changed.connect(UI.queue_update_relics)
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

	if ruin_service: ruin_service.free()

	_ensure_global_event_service()

	#create and setup services
	ruin_service = RuinService.new()
	add_child(ruin_service)
	ruin_service.initialise()

	trader_service = TraderService.new()
	add_child(trader_service)
	trader_service.initialise()

func _ensure_global_event_service() -> void: ##creates the run-owned global router before sibling services attempt to subscribe
	if is_instance_valid(global_event_service):
		return

	global_event_service = GlobalEventService.new()
	global_event_service.name = "GlobalEventService"
	add_child(global_event_service)

func publish_event(unit: Unit, event: GameEvent) -> void: ##routes one global event through effects and only its concrete subscriber bucket
	if is_instance_valid(global_event_service):
		global_event_service.publish(unit, event)

func subscribe_event(event_type: GameEvent.EventType, callback: Callable) -> void: ##registers a global subscriber for one concrete event type
	_ensure_global_event_service()
	global_event_service.subscribe(event_type, callback)

func subscribe_events(event_types: Array[GameEvent.EventType], callback: Callable) -> void: ##registers a global subscriber for several concrete event types
	_ensure_global_event_service()
	global_event_service.subscribe_many(event_types, callback)

func unsubscribe_event(event_type: GameEvent.EventType, callback: Callable) -> void: ##removes one typed global subscription
	if is_instance_valid(global_event_service):
		global_event_service.unsubscribe(event_type, callback)

func unsubscribe_events(event_types: Array[GameEvent.EventType], callback: Callable) -> void: ##removes several typed global subscriptions
	if is_instance_valid(global_event_service):
		global_event_service.unsubscribe_many(event_types, callback)

func is_subscribed_to_event(event_type: GameEvent.EventType, callback: Callable) -> bool: ##reports whether one typed global subscription is active
	return is_instance_valid(global_event_service) and global_event_service.is_subscribed(event_type, callback)


func begin_new_game() -> void: ##applies the selected guild once after island generation and before the first wave cycle
	var guild: GuildData = Run.current_guild
	flux = DEBUG_TEST_FLUX if DEBUG_GRANT_TEST_CONTENT else 30.0
	hp = 20.0
	self.unlocked_towers = {}
	for tower_type: Towers.Type in guild.starting_buildings:
		if Towers.is_tower_rite(tower_type):
			add_rite(tower_type, 1)
		else:
			unlock_tower(tower_type)

	relic_slot_capacity = maxi(relic_slot_capacity, guild.starting_relics.size())
	for relic: RelicData in guild.starting_relics:
		add_relic(relic)

	if DEBUG_GRANT_TEST_CONTENT:
		_grant_initial_test_content()

	trader_service.start_game()

	UI.queue_update_flux(flux)
	UI.queue_update_health(hp)
	UI.queue_update_relics()
	UI.queue_update_tower_types(unlocked_towers, rite_inventory)

func _grant_initial_test_content() -> void: ##adds the narrow debug palette for checking current refresh and chain interactions
	var test_tower_types: Array[Towers.Type] = _get_initial_test_tower_types()
	for tower_type: Towers.Type in test_tower_types:
		unlock_tower(tower_type)

	var test_rite_types: Array[Towers.Type] = _get_initial_test_rite_types()
	for rite_type: Towers.Type in test_rite_types:
		add_rite(rite_type, 1)

	var test_relics: Array[RelicData] = _get_initial_test_relics()
	relic_slot_capacity = maxi(relic_slot_capacity, test_relics.size())
	for relic: RelicData in test_relics:
		add_relic(relic)

func _get_initial_test_tower_types() -> Array[Towers.Type]: ##returns buildable tower unlocks that support current interaction testing
	return [
		Towers.Type.CANNON,
		Towers.Type.OUTPOST,
		Towers.Type.RESONATOR,
		Towers.Type.BLOOD_ALTAR,
	]

func _get_initial_test_rite_types() -> Array[Towers.Type]: ##returns learned rites that exercise current status, chain, refresh, and spatial effect work
	return [
		Towers.Type.RITE_BALANCE,
		Towers.Type.RITE_CURSES,
		Towers.Type.RITE_DRUMS,
		Towers.Type.RITE_RAMPAGE,
		Towers.Type.RITE_SACRIFICE,
	]

func _get_initial_test_relics() -> Array[RelicData]: ##returns reward-accessible relics that should be active in debug test starts
	return [
		Relics.SIGNAL_FLAG,
		Relics.TRANCE,
	]

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
func unlock_tower(tower_type : Towers.Type, unlock : bool = true) -> bool:
	if unlock and not can_add_tower_type(tower_type):
		return false

	if unlock:
		unlocked_towers[tower_type] = true
	else:
		unlocked_towers.erase(tower_type)
		if Towers.is_tower_rite(tower_type):
			rite_inventory.erase(tower_type)
	unlocked_towers_changed.emit(unlocked_towers, rite_inventory)
	return true

func get_active_tower_type_count() -> int: ##counts currently placeable non-rite tower types, without caring about towers already on the map
	var count: int = 0
	for tower_type: Towers.Type in unlocked_towers:
		if tower_type == Towers.Type.VOID or tower_type == Towers.Type.PLAYER_CORE:
			continue
		if Towers.is_tower_rite(tower_type):
			continue
		if not unlocked_towers[tower_type]:
			continue
		count += 1
	return count

func get_max_active_tower_types() -> int: ##returns the current active tower-loadout cap for ui and reward gates
	return MAX_ACTIVE_TOWER_TYPES

func has_free_tower_type_slot() -> bool: ##returns whether one more new non-rite tower type can enter the active placeable bar
	return get_active_tower_type_count() < MAX_ACTIVE_TOWER_TYPES

func can_add_tower_type(tower_type: Towers.Type) -> bool: ##allows duplicates and rites, but blocks new non-rite tower entries once the active loadout is full
	if tower_type == Towers.Type.VOID or tower_type == Towers.Type.PLAYER_CORE:
		return false
	if Towers.is_tower_rite(tower_type):
		return true
	if unlocked_towers.get(tower_type, false):
		return true
	return has_free_tower_type_slot()

func remove_tower_type(tower_type: Towers.Type) -> bool: ##removes a type from the active placeable bar without touching existing towers on the map
	if tower_type == Towers.Type.VOID or tower_type == Towers.Type.PLAYER_CORE:
		return false
	if not unlocked_towers.has(tower_type):
		return false

	unlocked_towers.erase(tower_type)
	if Towers.is_tower_rite(tower_type):
		rite_inventory.erase(tower_type)

	unlocked_towers_changed.emit(unlocked_towers, rite_inventory)
	return true

func is_tower_unlocked(tower_type : Towers.Type) -> bool:
	return unlocked_towers.get(tower_type, false)

func add_to_tower_limit(type: Towers.Type, amount: int) -> void:
	var current: int = _tower_limits.get(type, 0)
	_tower_limits[type] = current + amount
	#TODO: implement UI updates

func get_tower_limit(type: Towers.Type) -> int:
	return _tower_limits.get(type, -1)

func add_rite(type: Towers.Type, amount: int) -> bool:
	if not Towers.is_tower_rite(type):
		return false
	if amount <= 0:
		return unlocked_towers.get(type, false)
	if unlocked_towers.get(type, false):
		return true
	if not can_add_tower_type(type):
		return false

	rite_inventory[type] = 1
	unlocked_towers[type] = true
	unlocked_towers_changed.emit(unlocked_towers, rite_inventory)
	return true

func get_rite_count(type: Towers.Type) -> int: ##returns 1 once this rite has been permanently learned
	return 1 if unlocked_towers.get(type, false) else 0

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
	if not can_add_tower_type(tower.type):
		return

	self.flux -= RITE_EXCAVATION_COST
	if not add_rite(tower.type, 1):
		self.flux += RITE_EXCAVATION_COST
		return
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
		var rite_type: Towers.Type = int(unlocked_rite_type)
		if int(save_data.rite_inventory[unlocked_rite_type]) > 0 and Towers.is_tower_rite(rite_type):
			rite_inventory[rite_type] = 1
			unlocked_towers[rite_type] = true
	#readd relics in the sequence in which they were originally added
	for active_relic: Dictionary in save_data.relics:
		load_relic(active_relic)

	if save_data.has("trader"):
		trader_service.load_save_data(save_data.trader)
	trader_service.start_game()

	UI.queue_update_relics()
	UI.queue_update_flux(flux)
	UI.queue_update_health(hp)
	UI.queue_update_tower_types(unlocked_towers, rite_inventory)

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
		var tutorial_flag: int = int(tutorial_key)
		if completed_tutorials.has(tutorial_flag):
			completed_tutorials[tutorial_flag] = saved_tutorials[tutorial_key]
