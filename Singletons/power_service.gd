# power_service.gd (Autoload Singleton)
extends Node

var _disabled_towers: Array[Tower] = []
var _island_ref: Island # a reference to the active island

var _capacity_disabled: float

func _ready() -> void:
	# this service listens for player capacity changes to trigger its logic
	Player.capacity_changed.connect(_on_player_capacity_changed)
	set_process(false)

# should be called by the Island when it is ready
func register_island(island: Island) -> void:
	_island_ref = island

func _on_player_capacity_changed(_used: float, _total: float) -> void:
	if not is_instance_valid(_island_ref):
		return

	_disable_towers_for_deficit()
	_reenable_towers()

func _disable_towers_for_deficit() -> void:
	var towers: Array[Tower] = _island_ref.tower_grid.values()
	# sort by most recently constructed to shut them down first
	towers.sort_custom(func(a,b): return a.unit_id > b.unit_id)

	for tower: Tower in towers:
		var deficit_to_fill: float = -(Player.tower_capacity - (Player.used_capacity - _capacity_disabled))
		if deficit_to_fill <= 0:
			break
		# skip essential towers, capacity providers, or already disabled towers
		if tower in _disabled_towers or \
		tower.type == Towers.Type.GENERATOR or tower.type == Towers.Type.PLAYER_CORE:
			continue
		# skip towers with no capacity cost
		if is_zero_approx(Towers.get_tower_capacity(tower.type)):
			continue
			
		if not tower.disabled:
			tower.disabled = true
			_disabled_towers.append(tower)
			_capacity_disabled += Towers.get_tower_capacity(tower.type)

func _reenable_towers() -> void:
	var capacity_to_reenable: float = Player.tower_capacity - (Player.used_capacity - _capacity_disabled) 
	if capacity_to_reenable <= 0:
		return

	for i: int in range(_disabled_towers.size() - 1, -1, -1):
		var tower: Tower = _disabled_towers[i]
		if not is_instance_valid(tower):
			continue

		var tower_cap_cost: float = Towers.get_tower_capacity(tower.type)
		
		if capacity_to_reenable >= tower_cap_cost:
			tower.disabled = false
			capacity_to_reenable -= tower_cap_cost #we need to update our internal counter to account for this new change
			_capacity_disabled -= tower_cap_cost #update global counter
			_disabled_towers.remove_at(i)
