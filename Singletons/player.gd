# player.gd
# this script can be seen as the "agent" of the player interacting with game logic and UI
extends Node

signal flux_changed(new_flux: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary[Towers.Type, bool])

#inclusion in Player is merited by their clear player-side nature.
#various player-side states.
var flux: float = 20.0:
	set(value):
		flux = value
		flux_changed.emit(flux)

var used_capacity: float = 0.0:
	set(value):
		used_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)
		
var tower_capacity: float = 0.0:
	set(value):
		tower_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)
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

var unlocked_towers: Dictionary[Towers.Type, bool] = {}:
	set(value):
		unlocked_towers = value
		unlocked_towers_changed.emit(unlocked_towers)
#tower unlock helper functions
func unlock_towers(tower_type : Towers.Type, unlock : bool = true):
	unlocked_towers[tower_type] = unlock
	
func is_tower_unlocked(tower_type : Towers.Type) -> bool:
	return unlocked_towers.get(tower_type, false)

func _ready():
	#initial state setup
	self.unlocked_towers = {
		Towers.Type.PALISADE: true,
		Towers.Type.GENERATOR: true,
		Towers.Type.TURRET: true,
		Towers.Type.AMPLIFIER: true,
		Towers.Type.CANNON: true,
		Towers.Type.FROST_TOWER: true,
	}
	#connect to UI player input signals
	UI.place_tower_requested.connect(_on_place_tower_requested)
	UI.sell_tower_requested.connect(_on_sell_tower_requested)
	#couple playerside logic signals with UI output signals
	flux_changed.connect(UI.update_flux.emit)
	capacity_changed.connect(UI.update_capacity.emit)
	unlocked_towers_changed.connect(UI.update_tower_types.emit)
	
# MODIFIED: Tower placement request now focuses only on player-side checks.
# It asks the Island to handle the actual placement validation and construction.
func _on_place_tower_requested(tower_type: Towers.Type, cell: Vector2i, facing: Tower.Facing):
	# 1. Check player's own resources.
	if not unlocked_towers.get(tower_type, false):
		return
		
	if flux < Towers.get_tower_cost(tower_type):
		return
		
	if used_capacity + Towers.get_tower_capacity(tower_type) > tower_capacity:
		# NOTE: You could add a UI warning here about insufficient capacity.
		return

	# 2. Ask the Island to perform the placement. The Island is responsible for world checks.
	var success = References.island.request_tower_placement(cell, tower_type, facing)
	
	# 3. If the Island confirms placement, deduct resources.
	if success:
		self.flux -= Towers.get_tower_cost(tower_type)
		#TODO: Towers.update_tower_cost(tower_type, 1)

func _on_sell_tower_requested(tower : Tower):
	tower.sell()
