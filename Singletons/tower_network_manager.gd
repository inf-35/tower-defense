# tower_network_manager.gd (Autoload Singleton)
extends Node
#this singleton manages inter-tower effects/relationships
#it merely evaluates/manages abstract connections, whereas the actual functionality is delegated to handlers

enum NetworkType {
	PRISM,
}

var PRISM_LASER_SCENE: PackedScene

# --- state ---
# we store towers by their network type
var _network_towers: Dictionary[NetworkType, Array] = {}
#index towers by id
var _towers_by_id: Dictionary[int, Tower] = {}
# index handlers by tower
var _handlers: Dictionary[Tower, Node] = {}

# we store the active prism laser links to manage them
var _active_prism_links: Array[Vector2i] = []

func start() -> void:
	# listen for any grid change to trigger a full rebuild of all networks
	References.island.tower_changed.connect(_on_grid_changed)

# --- public api ---
func register_tower(tower: Tower, network_type: NetworkType, handler: Node = tower) -> void:
	if not _network_towers.has(network_type):
		_network_towers[network_type] = []
	_network_towers[network_type].append(tower)
	
	assert(handler.has_method(&"create_link")) #NOTE: contract for handlers to follow
	assert(handler.has_method(&"remove_link")) #signature is create_link(partner), where partner is the Tower being linked to
	_towers_by_id[tower.unit_id] = tower #index the tower by unit id
	_handlers[tower] = handler #the handler is the node that is delegated functionality
	_on_grid_changed() # trigger a rebuild when a new network tower is registered

func deregister_tower(tower: Tower, network_type: NetworkType) -> void:
	_network_towers[network_type].erase(tower) #NOTE: the tower must deregister themselves manually before dying
	_on_grid_changed()
	_towers_by_id.erase(tower.unit_id) #these must be done after network resolution, as removal effects
	_handlers.erase(tower) #require these indexes

# --- signal handlers ---
func _on_grid_changed(_position: Vector2i = Vector2i.ZERO) -> void:
	# this is the single, centralized update function
	# currently it only manages prisms, but could manage other networks too
	_rebuild_prism_network()

# this function is rewritten to support many-to-many links without duplication
func _rebuild_prism_network() -> void:
	if not _network_towers.has(NetworkType.PRISM):
		_network_towers[NetworkType.PRISM] = []

	var newly_active_links: Array[Vector2i] = []
	var prisms: Array[Tower] = []
	prisms.assign(_network_towers[NetworkType.PRISM]) #type conversion from Array to Array[Tower]
	
	var island: Island = References.island
	# this dictionary will track processed pairs to prevent duplicate links
	var processed_links: Dictionary[Vector2i, bool] = {}
	# 2. find all valid, unique pairs and create links
	for prism_a: Tower in prisms:
		for prism_b: Tower in prisms:
			# skip self-comparison
			if prism_a == prism_b:
				continue

			# --- canonical key generation to prevent duplicates ---
			# we create a unique, order-independent key for the pair (A, B).
			# this ensures we don't process (B, A) if we've already done (A, B).
			var id_a: int = prism_a.unit_id
			var id_b: int = prism_b.unit_id
			var link_key: Vector2i = Vector2i(mini(id_a, id_b), maxi(id_a, id_b))
			
			if processed_links.has(link_key):
				continue # this pair has already been processed
			processed_links[link_key] = true # mark this pair as processed for all future iterations
			
			# --- link validation ---
			var pos_a: Vector2i = prism_a.tower_position
			var pos_b: Vector2i = prism_b.tower_position

			# check if they are on the same X or Y axis
			if pos_a.x == pos_b.x or pos_a.y == pos_b.y:
				# check for obstructions between them
				var path_clear: bool = true
				var line: Array[Vector2i] = _get_line_between(pos_a, pos_b)
				for cell: Vector2i in line:
					# a cell is an obstruction if it has a tower that is marked as 'blocking'
					# unless it is the player core, which should still be counted as solid despite being non-blocking
					if island.tower_grid.has(cell) and (island.tower_grid[cell].blocking or island.tower_grid[cell].type == Towers.Type.PLAYER_CORE):
						path_clear = false
						break
				
				# 3. if the link is valid, create the laser entity
				if path_clear:
					newly_active_links.append(link_key)

	for previously_active_link: Vector2i in _active_prism_links:
		if not newly_active_links.has(previously_active_link):
			var tower_a: Tower = _towers_by_id[previously_active_link.x]
			var tower_b: Tower = _towers_by_id[previously_active_link.y]
			print("removed link!")
			_handlers[tower_a].remove_link(tower_b)
			
	for newly_active_link: Vector2i in newly_active_links:
		if not _active_prism_links.has(newly_active_link):
			var tower_a: Tower = _towers_by_id[newly_active_link.x]
			var tower_b: Tower = _towers_by_id[newly_active_link.y]
			_handlers[tower_a].create_link(tower_b)
	
	_active_prism_links = newly_active_links

# simple Bresenham's line algorithm variant to find cells between two points
func _get_line_between(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var line: Array[Vector2i] = []
	var dx: int = abs(to.x - from.x)
	var dy: int = abs(to.y - from.y)
	
	# for perfectly horizontal or vertical lines
	if dx == 0:
		for y: int in range(min(from.y, to.y) + 1, max(from.y, to.y)):
			line.append(Vector2i(from.x, y))
	elif dy == 0:
		for x: int in range(min(from.x, to.x) + 1, max(from.x, to.x)):
			line.append(Vector2i(x, from.y))
			
	return line
