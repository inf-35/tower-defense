#player.gd
#this script can be seen as the "agent" of the player interacting with game logic and ui
extends Node
class_name Player

signal flux_changed(new_flux: float)
signal hp_changed(new_health: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary[Towers.Type, bool])
signal relics_changed()

signal on_event(unit: Unit, game_event: GameEvent) ##global event signal bus, collects events from all units
#and relevant towers

const DEBUG_CAPACITY: bool = false
const RITE_EXCAVATION_COST: float = 3.0

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

var _active_effects_container: Node

#tutorial
enum TutorialFlag {
	MAIN,
	TROLL,
	TOWER_DESTROYED,
}

var completed_tutorials: Dictionary[TutorialFlag, bool] = {
	TutorialFlag.MAIN: false,
	TutorialFlag.TROLL: false,
	TutorialFlag.TOWER_DESTROYED: false,
}

#various services (which are children of this node)
var ruin_service: RuinService
var global_event_service: GlobalEventService
var trader_service: TraderService

func _ready() -> void:
	if not OS.has_feature("web"): #web builds are automatically resized
		get_window().size = DisplayServer.screen_get_size() * 0.6
		get_window().move_to_center()
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
	#Run.phases.wave_ended.connect(func(_wave):
		#Run.player.flux += 6
	#)

func start() -> void:
	for unit: Unit in get_tree().get_nodes_in_group(Run.references.TOWER_GROUP):
		unit.queue_free()

	for unit: Unit in get_tree().get_nodes_in_group(Run.waves.ENEMY_GROUP):
		unit.queue_free()

	rite_inventory.clear()
	_tower_limits.clear()
	unlocked_towers.clear()
	active_relics.clear()

	tower_capacity = 0.0
	used_capacity = 0.0

	if _active_effects_container: _active_effects_container.free()
	if global_event_service: global_event_service.free()
	if ruin_service: ruin_service.free()

	#setup event bus
	global_event_service = GlobalEventService.new()
	add_child(global_event_service)
	global_event_service.initialise_event_bus(on_event)

	#setup global effects container
	_active_effects_container = Node.new()
	_active_effects_container.name = "ActiveGlobalEffects"
	add_child(_active_effects_container)

	#create and setup services
	ruin_service = RuinService.new()
	add_child(ruin_service)
	ruin_service.initialise()

	trader_service = TraderService.new()
	add_child(trader_service)
	trader_service.initialise()


func begin_new_game() -> void:
	#initial state setup
	self.unlocked_towers = {
		Towers.Type.TURRET: true,
		Towers.Type.PALISADE: true,
		Towers.Type.FARM: true,
		Towers.Type.GENERATOR: true,
		Towers.Type.POISON: true,
		Towers.Type.FROST_TOWER: true,
	}

	var reward := Reward.new()
	#reward.type = Reward.Type.ADD_RITE
	#reward.rite_type = Towers.Type.RITE_GLASS
	#RewardService.apply_reward(reward)
	#reward.rite_type = Towers.Type.RITE_SACRIFICE
	#RewardService.apply_reward(reward)
	#reward.type = Reward.Type.ADD_RELIC
	#reward.relic = Relics.EPIDEMIC
	#RewardService.apply_reward(reward)
	#reward.relic = Relics.RUPTURED_HEART
	#RewardService.apply_reward(reward)

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
	active_relics.append(relic)

	if relic.global_effect:
		global_event_service.register_effect(relic.global_effect)

	if relic.active_effect_scene:
		#instantiate the logic node for the active relic
		var effect_node: Node = relic.active_effect_scene.instantiate()
		#add it to our container so it becomes part of the scene tree
		_active_effects_container.add_child(effect_node)
		print("Added relic global effect: ", effect_node)
		#initialize it with its own data
		effect_node.initialise()

	#announce that the global state has changed
	relics_changed.emit()

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
	self.flux -= Towers.get_tower_cost(tower_type)
	var success = Run.references.island.request_tower_placement(cell, tower_type, facing)

	#3. if the island confirms placement, deduct resources.
	if success:
		Audio.play_sound(ID.Sounds.TOWER_PLACED_SOUND, 0.0, Island.cell_to_position(cell))

		if Towers.is_tower_rite(tower_type):
			self.add_rite(tower_type, -1)
	else:
		self.flux += Towers.get_tower_refund_value(tower_type)

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
	active_relics.append(relic)

	if relic.global_effect:
		var effect_instance := global_event_service.register_effect(relic.global_effect)
		effect_instance.effect_prototype.load_save_data(effect_instance, active_relic)

	if relic.active_effect_scene: #WARNING: this doesnt actually work
		#instantiate the logic node for the active relic
		var effect_node: Node = relic.active_effect_scene.instantiate()
		#add it to our container so it becomes part of the scene tree
		_active_effects_container.add_child(effect_node)
		print("Added relic global effect: ", effect_node)
		#initialize it with its own data
		effect_node.initialise()


	#announce that the global state has changed
	relics_changed.emit()

func get_profile() -> Dictionary:
	var profile_data: Dictionary = {
		"completed_tutorials": completed_tutorials,
	}
	return profile_data

func load_profile(profile_data: Dictionary) -> void:
	for tutorial_key: String in profile_data.get("completed_tutorials"):
		completed_tutorials[int(tutorial_key)] = profile_data.get("completed_tutorials")[tutorial_key]
