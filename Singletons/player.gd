# player.gd
# this script can be seen as the "agent" of the player interacting with game logic and UI
extends Node

signal flux_changed(new_flux: float)
signal hp_changed(new_health: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary[Towers.Type, bool])
signal relics_changed()

#inclusion in Player is merited by their clear player-side nature.
#various player-side states.
var flux: float = 200.0:
	set(value):
		flux = value
		flux_changed.emit(flux)
		
var hp: float = 20.0:
	set(value):
		hp = value
		hp_changed.emit(hp)

var used_capacity: float = 0.0:
	set(value):
		used_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)
		
var tower_capacity: float = 0.0:
	set(value):
		push_warning(">>?")
		tower_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)
		
var unlocked_towers: Dictionary[Towers.Type, bool] = {}:
	set(value):
		unlocked_towers = value
		unlocked_towers_changed.emit(unlocked_towers)
		
var active_relics: Array[RelicData]

var _active_effects_container: Node

#various services (which are children of this node)
var ruin_service: RuinService

func _ready():
	#connect to UI player input signals
	UI.place_tower_requested.connect(_on_place_tower_requested)
	UI.sell_tower_requested.connect(_on_sell_tower_requested)
	#couple playerside logic signals with UI output signals
	flux_changed.connect(UI.update_flux.emit)
	capacity_changed.connect(UI.update_capacity.emit)
	hp_changed.connect(UI.update_health.emit)
	unlocked_towers_changed.connect(UI.update_tower_types.emit)
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
		Towers.Type.CANNON: true,
		Towers.Type.TURRET: true,
	}
	flux = 15.0
	#RewardService.apply_reward(Reward.new(Reward.Type.ADD_RELIC, {ID.Rewards.RELIC: preload("res://Content/Relics/increase_ruin_chance.tres")}))
	

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
	unlocked_towers_changed.emit(unlocked_towers)
	
func is_tower_unlocked(tower_type : Towers.Type) -> bool:
	return unlocked_towers.get(tower_type, false)
	
#relic entry point (to add new relics)
func add_relic(relic: RelicData) -> void:
	if not is_instance_valid(relic):
		return
	active_relics.append(relic)
	
	if relic.active_effect_scene:
		# instantiate the logic node for the active relic
		var effect_node: GlobalEffect = relic.active_effect_scene.instantiate()
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
		if _unit_matches_target(unit, relic) and relic.modifier_prototype != null:
			var new_modifier := relic.modifier_prototype.generate_modifier()
			# brand it with a source ID for debugging, if needed
			new_modifier.source_id = -1 # use a special ID for global mods
			relevant_modifiers.append(new_modifier)
			
	return relevant_modifiers
# internal helper for checking targeting rules
func _unit_matches_target(unit: Unit, relic: RelicData) -> bool:
	match relic.target_type:
		RelicData.TargetType.ALL_TOWERS:
			return unit is Tower
		RelicData.TargetType.ALL_ENEMIES:
			return not (unit is Tower) # a simple proxy for being an enemy
		RelicData.TargetType.SPECIFIC_TOWER_TYPE:
			return unit is Tower and unit.type == relic.specific_tower_type
		RelicData.TargetType.PLAYER:
			# this would apply to player-specific stats like starting flux, etc.
			# not implemented in ModifiersComponent yet, but the structure supports it
			return false 
			
	return false
# MODIFIED: Tower placement request now focuses only on player-side checks.
# it asks the Island to handle the actual placement validation and construction.
func _on_place_tower_requested(tower_type: Towers.Type, cell: Vector2i, facing: Tower.Facing):
	# 1. Check player's own resources.
	if not unlocked_towers.get(tower_type, false):
		return
		
	if flux < Towers.get_tower_cost(tower_type):
		return
	
	if not (tower_type == Towers.Type.GENERATOR and References.island.get_terrain_base(cell) == Terrain.Base.RUINS):
		if used_capacity + Towers.get_tower_capacity(tower_type) > tower_capacity:
			# NOTE: You could add a UI warning here about insufficient capacity.
			return

	# 2. Ask the Island to perform the placement. The Island is responsible for world checks.
	var success = References.island.request_tower_placement(cell, tower_type, facing)
	
	# 3. If the Island confirms placement, deduct resources.
	if success:
		self.flux -= Towers.get_tower_cost(tower_type)
		#TODO: Towers.update_tower_cost(tower_type, 1)

func _on_sell_tower_requested(tower):
	if not is_instance_valid(tower):
		return
	if tower is Tower:
		tower.sell()
