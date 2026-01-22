# player.gd
# this script can be seen as the "agent" of the player interacting with game logic and UI
extends Node

signal flux_changed(new_flux: float)
signal hp_changed(new_health: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary[Towers.Type, bool])
signal relics_changed()

signal on_event(unit: Unit, game_event: GameEvent) ##global event signal bus, collects events from all units
#and relevant towers 

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
			if not Phases.is_game_over:
				Phases.start_game_over(false)

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

#various services (which are children of this node)
var ruin_service: RuinService
var global_event_service: GlobalEventService

func _ready():
	if not OS.has_feature("web"): # web builds are automatically resized
		get_window().size = DisplayServer.screen_get_size() * 0.8
		get_window().move_to_center()
	#connect to UI player input signals
	UI.place_tower_requested.connect(_on_place_tower_requested)
	UI.sell_tower_requested.connect(_on_sell_tower_requested)
	UI.upgrade_tower_requested.connect(_on_upgrade_tower_requested)
	UI.reward_rerolled.connect(_on_reward_reroll_requested)
	#couple playerside logic signals with UI output signals
	flux_changed.connect(UI.update_flux.emit)
	capacity_changed.connect(UI.update_capacity.emit)
	hp_changed.connect(UI.update_health.emit)
	unlocked_towers_changed.connect(UI.update_tower_types.emit)
	relics_changed.connect(UI.update_relics.emit)
	
	Phases.wave_ended.connect(func(_wave):
		Player.flux += 6
	)

func start():
	for unit: Unit in get_tree().get_nodes_in_group(References.TOWER_GROUP):
		unit.queue_free()
		
	for unit: Unit in get_tree().get_nodes_in_group(Waves.ENEMY_GROUP):
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
	
	References.references_ready.connect(_setup_state, CONNECT_ONE_SHOT)

func _setup_state():
	#initial state setup
	self.unlocked_towers = {
		Towers.Type.PALISADE: true,
		Towers.Type.GENERATOR: true,
		Towers.Type.TURRET: true,
	}
	add_rite(Towers.Type.RITE_LIBERTY, 20)
	#add_rite(Towers.Type.RITE_FLAME, 20)
	#add_rite(Towers.Type.RITE_FROST, 20)
	#
	var reward := Reward.new()
	reward.type = Reward.Type.ADD_RELIC
	reward.relic = Relics.PAWN_STRUCTURE
	RewardService.apply_reward(reward)
	#reward.relic = Relics.MACUAHUITL
	#RewardService.apply_reward(reward)
	#reward.relic = Relics.EARLY_BIRD
	#RewardService.apply_reward(reward)
	
	flux = 20.0
	hp = 20.0
	
	UI.update_inspector_bar.emit(Towers.get_tower_prototype(Towers.Type.TURRET))
	UI.update_relics.emit()
	UI.update_flux.emit(flux)
	UI.update_health.emit(hp)

#capacity helper functions
func add_to_used_capacity(amount: float):
	self.used_capacity += amount

func remove_from_used_capacity(amount: float):
	self.used_capacity -= amount
	
func add_to_total_capacity(amount : float):
	self.tower_capacity += amount

func remove_from_total_capacity(amount : float):
	self.tower_capacity -= amount
	
func has_capacity(tower_type : Towers.Type) -> bool:
	return Player.used_capacity + Towers.get_tower_capacity(tower_type) - 0.01 < Player.tower_capacity

#tower unlock helper functions
func unlock_tower(tower_type : Towers.Type, unlock : bool = true):
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
		# instantiate the logic node for the active relic
		var effect_node: Node = relic.active_effect_scene.instantiate()
		# add it to our container so it becomes part of the scene tree
		_active_effects_container.add_child(effect_node)
		print("Added relic global effect: ", effect_node)
		# initialize it with its own data
		effect_node.initialise()

	# announce that the global state has changed
	relics_changed.emit()

# this is the core query function used by ModifiersComponent
func get_modifiers_for_unit(unit: Unit) -> Array[Modifier]:
	var relevant_modifiers: Array[Modifier] = []
	
	for relic: RelicData in active_relics:
		# check if the unit matches the relic's targeting rules
		for modifier_prototype: GlobalModifierPrototype in relic.modifier_prototypes:
			if not modifier_prototype.matches_unit(unit):
				continue
			var new_modifier : Modifier = modifier_prototype.generate_modifier()
			# brand it with a source ID for debugging, if needed
			new_modifier.source_id = -1 # use a special ID for global mods
			relevant_modifiers.append(new_modifier)

	return relevant_modifiers
	
# MODIFIED: Tower placement request now focuses only on player-side checks.
# it asks the Island to handle the actual placement validation and construction.
func _on_place_tower_requested(tower_type: Towers.Type, cell: Vector2i, facing: Tower.Facing):
	# 1. Check player's own resources.
	if not unlocked_towers.get(tower_type, false):
		return
		
	if flux < Towers.get_tower_cost(tower_type):
		return
	
	if not (tower_type == Towers.Type.GENERATOR and References.island.get_terrain_base(cell) == Terrain.Base.SETTLEMENT):
		if used_capacity + Towers.get_tower_capacity(tower_type) > tower_capacity:
			# NOTE: You could add a UI warning here about insufficient capacity.
			return

	# 2. Ask the Island to perform the placement. The Island is responsible for world checks.
	var success = References.island.request_tower_placement(cell, tower_type, facing)
	
	# 3. If the Island confirms placement, deduct resources.
	if success:
		Audio.play_sound(ID.Sounds.TOWER_PLACED_SOUND, 0.0, Island.cell_to_position(cell))
		self.flux -= Towers.get_tower_cost(tower_type)
		
		if Towers.is_tower_rite(tower_type):
			self.add_rite(tower_type, -1)
		#TODO: Towers.update_tower_cost(tower_type, 1)

func _on_sell_tower_requested(tower):
	if not is_instance_valid(tower):
		return
	if tower is Tower:
		tower.sell()
		
func _on_upgrade_tower_requested(old_tower: Tower, upgrade_type: Towers.Type):
	var cost: float = Towers.get_tower_upgrade_cost(old_tower.type, upgrade_type)
	if self.flux < cost:
		return
	
	var success: bool = References.island.request_upgrade(old_tower, upgrade_type)
	
	if success:
		self.flux -= cost

func _on_reward_reroll_requested():
	var cost: float = RewardService.get_reroll_cost()
	if self.flux < cost:
		return
	self.flux -= cost
	RewardService.reroll()
