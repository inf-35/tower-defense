extends Behavior
class_name DrumRiteBehavior

@export var trigger_chance: float = 0.20

#tracks currently connected towers to avoid double connections
var _connected_neighbors: Dictionary[Tower, bool] = {}

func start() -> void:
	var tower = unit as Tower
	#hook into grid updates to maintain connections
	tower.adjacency_updated.connect(_refresh_connections)
	
	#initial setup
	attach()
	
func detach(): # disconnect all 
	var to_remove = []
	for tower in _connected_neighbors:
		if is_instance_valid(tower):
			if tower.on_event.is_connected(_on_neighbor_event):
				tower.on_event.disconnect(_on_neighbor_event)
		to_remove.append(tower)
	
	for t in to_remove:
		_connected_neighbors.erase(t)
		
func attach(): 
	_refresh_connections((unit as Tower).get_adjacent_towers())

func _refresh_connections(adj_map: Dictionary[Vector2i, Tower]) -> void:
	var current_set: Dictionary[Tower, bool] = {}
	
	# connect new neighbors
	for neighbor: Tower in adj_map.values():
		if not is_instance_valid(neighbor): continue
		
		current_set[neighbor] = true
		
		if not _connected_neighbors.has(neighbor):
			# subscribe specifically to this neighbor's bus
			neighbor.on_event.connect(_on_neighbor_event.bind(neighbor))
			_connected_neighbors[neighbor] = true

	# disconnect old neighbors
	var to_remove = []
	for old_t in _connected_neighbors:
		if not current_set.has(old_t):
			# check validity before disconnecting (it might be freed already)
			if is_instance_valid(old_t):
				if old_t.on_event.is_connected(_on_neighbor_event):
					old_t.on_event.disconnect(_on_neighbor_event)
			to_remove.append(old_t)
			
	for t in to_remove:
		_connected_neighbors.erase(t)

# This handler is ONLY called when a direct neighbor fires
func _on_neighbor_event(event: GameEvent, source_neighbor: Tower) -> void:
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return
		
	# 1. Roll Chance
	if randf() > trigger_chance: return
	
	# 2. Trigger Others
	# We iterate our known list (which we know are valid neighbors)
	_trigger_all_except(source_neighbor)

func _trigger_all_except(exception: Tower) -> void:
	for t in _connected_neighbors:
		if t == exception: continue
		if is_instance_valid(t) and is_instance_valid(t.attack_component):
			t.attack_component.current_cooldown = 0.0
			
func draw_visuals(canvas: RangeIndicator) -> void:
	draw_visuals_adjacent_tiles(canvas)
