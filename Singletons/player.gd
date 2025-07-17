# player.gd
# MODIFIED: This script is now a data-centric manager for the player's state (flux, capacity).
# It no longer handles world logic like disabling towers or validating placement.
# It communicates state changes via signals.
extends Node

# MODIFIED: Signals are more specific and used for decoupling.
signal flux_changed(new_flux: float)
signal capacity_changed(used: float, total: float)
signal unlocked_towers_changed(unlocked: Dictionary)

# RETAINED: Flux management is a core player responsibility.
var flux: float = 20.0:
	set(value):
		flux = value
		flux_changed.emit(flux)
		UI.update_flux.emit(flux)

# MODIFIED: Setters no longer call a complex logic function (_check_capacity_status).
# They now simply emit a signal that other nodes (like Island and UI) can listen to.
var used_capacity: float = 0.0:
	set(value):
		used_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)
		
var tower_capacity: float = 0.0:
	set(value):
		tower_capacity = value
		capacity_changed.emit(used_capacity, tower_capacity)

# RETAINED: Unlocked tower data is player-specific.
var unlocked_towers: Dictionary[Towers.Type, bool] = {}:
	set(value):
		unlocked_towers = value
		unlocked_towers_changed.emit(unlocked_towers)

# RETAINED: Player-side global data.
var effect_prototypes: Array[EffectPrototype] = []

func _ready():
	# Initial state setup
	self.unlocked_towers = {
		Towers.Type.PALISADE: true,
		Towers.Type.GENERATOR: true,
		Towers.Type.TURRET: true,
	}
	
	# RETAINED: Still connects to the input handler.
	UI.place_tower_requested.connect(_on_place_tower_requested)
	UI.sell_tower_requested.connect(_on_sell_tower_requested)
	
# REMOVED: All power management logic (_check_capacity_status, disable_towers_for_deficit, reenable_towers)
# has been moved to island.gd, which is responsible for managing the towers.

# REMOVED: compute_capacity(). Capacity is now updated additively by towers when they
# are created or destroyed, which is more efficient than recalculating.

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
	var success = References.island.request_tower_placement(tower_type, cell, facing)
	
	# 3. If the Island confirms placement, deduct resources.
	if success:
		self.flux -= Towers.get_tower_cost(tower_type)
		#TODO: Towers.update_tower_cost(tower_type, 1)

func _on_sell_tower_requested(tower : Tower):
	tower.sell()
# ADDED: New functions for additively changing total capacity.
# These should be called by capacity-providing towers (e.g., Generators)
# when they are built and destroyed.
func add_to_used_capacity(amount: float):
	self.used_capacity += amount

func remove_from_used_capacity(amount: float):
	self.used_capacity -= amount
	
func add_to_total_capacity(amount : float):
	self.tower_capacity += amount

func remove_from_total_capacity(amount : float):
	self.tower_capacity -= amount
	
func has_capacity(tower_type : Towers.Type) -> bool:
	return Player.used_capacity + Towers.get_tower_capacity(tower_type) < Player.tower_capacity
