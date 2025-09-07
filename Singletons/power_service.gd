# power_service.gd (Autoload Singleton)
extends Node

var _disabled_towers: Array[Tower] = []
var _island_ref: Island # a reference to the active island

func _ready() -> void:
	# this service listens for player capacity changes to trigger its logic
	Player.capacity_changed.connect(_on_player_capacity_changed)

# should be called by the Island when it is ready
func register_island(island: Island) -> void:
	_island_ref = island

func _on_player_capacity_changed(used: float, total: float) -> void:
	if not is_instance_valid(_island_ref):
		return
		
	if used > total:
		var deficit: float = used - total
		_disable_towers_for_deficit(deficit)
	else:
		_reenable_towers()

func _disable_towers_for_deficit(deficit: float) -> void:
	var towers: Array[Tower] = _island_ref.tower_grid.values()
	# sort by most recently constructed to shut them down first
	towers.sort_custom(func(a,b): return a.unit_id > b.unit_id)
	
	var deficit_to_fill: float = deficit
	for tower: Tower in towers:
		if deficit_to_fill <= 0:
			break
			
		# skip essential towers, capacity providers, or already disabled towers
		if tower in _disabled_towers or \
		tower.type == Towers.Type.GENERATOR or tower.type == Towers.Type.PLAYER_CORE:
			continue
			
		if not tower.disabled:
			tower.disabled = true
			_disabled_towers.append(tower)
			deficit_to_fill -= Towers.get_tower_capacity(tower.type)

func _reenable_towers() -> void:
	if Player.used_capacity > Player.tower_capacity:
		return

	var capacity_surplus: float = Player.tower_capacity - Player.used_capacity
	
	# iterate backwards to reactivate in reverse order of deactivation
	for i: int in range(_disabled_towers.size() - 1, -1, -1):
		var tower: Tower = _disabled_towers[i]
		if not is_instance_valid(tower):
			continue

		var tower_cap_cost: float = Towers.get_tower_capacity(tower.type)
		
		if capacity_surplus >= tower_cap_cost:
			tower.disabled = false
			capacity_surplus -= tower_cap_cost
			_disabled_towers.remove_at(i)
