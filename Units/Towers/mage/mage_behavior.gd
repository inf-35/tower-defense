extends Behavior
class_name MageBehavior

@export var network_tint: Color = Color(0.9, 0.7, 1.0, 1.0) # Purple

var _connected_palisades: Array[Tower] = [] ##the list of palisades this specific Mage is currently powering

func start() -> void:
	Player.on_event.connect(_on_global_event) ##listen globally for any tower changes to recalculate the contiguous network
	_recalculate_network()

func detach() -> void:
	# Cleanup: If the Mage is destroyed/sold, untint everything
	for p in _connected_palisades:
		_set_palisade_tint(p, false)
	_connected_palisades.clear()

func update(_delta: float) -> void:
	if _is_attack_possible(false):
		_pulse_network()

func _pulse_network() -> void:
	attack_component.refresh_cooldown()
	# pre-calculate the Mage's stats (Damage, Range, Statuses)
	# relics applied to the Mage will buff these values here!
	var dmg = attack_component.damage
	var radius = attack_component.radius
	
	# TODO: visual feedback on the Mage itself
	if is_instance_valid(animation_player):
		_play_animation(&"cast")
	
	# command connected palisades to attack
	for palisade: Tower in _connected_palisades:
		if not is_instance_valid(palisade): continue
		
		var hit_data = attack_component.attack_data.generate_generic_hit_data()
		hit_data.source = unit # mage gets credit
		hit_data.target = null # untargeted aoe
		hit_data.target_affiliation = true
		hit_data.damage = dmg
		hit_data.radius = radius
		
		var delivery := DeliveryData.new()
		delivery.delivery_method = DeliveryData.DeliveryMethod.CONE_AOE
		delivery.use_source_position_override = true
		delivery.source_position = palisade.global_position
		delivery.cone_angle = 360.0
		
		unit.deal_hit(hit_data, delivery)
		
		#play the VFX defined in the Mage's attack data on the palisade
		if hit_data.vfx_on_spawn:
			VFXManager.play_vfx(hit_data.vfx_on_spawn, palisade.global_position, Vector2.UP)

#network management
func _on_global_event(_unit: Unit, event: GameEvent) -> void:
	if event.event_type == GameEvent.EventType.TOWER_BUILT or event.event_type == GameEvent.EventType.DIED or event.event_type == GameEvent.EventType.REPLACED:
		if event.event_type == GameEvent.EventType.TOWER_BUILT and (event.data as BuildTowerData).tower.type != Towers.Type.PALISADE:
			return
		if event.event_type == GameEvent.EventType.DIED and (event.data as HitReportData).target is Tower and ((event.data as HitReportData).target as Tower).type != Towers.Type.PALISADE:
			return
		_recalculate_network.call_deferred()

func _recalculate_network() -> void:
	if  unit.abstractive: return
	var new_network: Array[Tower] = _calculate_contiguous_palisades((unit as Tower).tower_position)
	# --- Apply Diff for Tinting ---
	
	# 1. Remove tint from disconnected palisades
	for old_p: Tower in _connected_palisades:
		if is_instance_valid(old_p) and not new_network.has(old_p):
			_set_palisade_tint(old_p, false)
			
	# 2. Add tint to newly connected palisades
	for new_p: Tower in new_network:
		if not _connected_palisades.has(new_p):
			_set_palisade_tint(new_p, true)
			
	_connected_palisades = new_network
	
func _calculate_contiguous_palisades(start_cell: Vector2i) -> Array[Tower]:
	var island = References.island
	if not is_instance_valid(island): return []
	if not is_instance_valid(unit): return []
	if unit.disabled: return []
	
	var network: Array[Tower] = []
	var visited_cells: Dictionary = {}
	var queue: Array[Vector2i] = [start_cell]
	
	while queue.size() > 0:
		var curr_cell = queue.pop_front()
		if visited_cells.has(curr_cell): continue
		visited_cells[curr_cell] = true
		
		var t = island.get_tower_on_tile(curr_cell)
		
		if curr_cell == start_cell and not is_instance_valid(t):
			for dir in island.DIRS:
				queue.append(curr_cell + dir)
		if not is_instance_valid(t):
			continue
		
		# valid nodes: the starting cell (which might be empty ground in Preview), or Palisades
		if curr_cell == start_cell or (t.type == Towers.Type.PALISADE and not t.disabled):
			if t.type == Towers.Type.PALISADE and not t.disabled:
				# prevent duplicate adds for multi-tile palisades
				if not network.has(t):
					network.append(t)
				
			# queue neighbors
			for adj_cell in t.get_adjacent_cells():
				if not visited_cells.has(adj_cell):
					queue.append(adj_cell)
					
	return network
	
func _set_palisade_tint(palisade: Tower, is_connected: bool) -> void:
	if not is_instance_valid(palisade) or not is_instance_valid(palisade.graphics): return
	
	# Track how many mages are connected
	var mage_count: int = palisade.get_meta(&"mage_count", 0)
	
	if is_connected:
		mage_count += 1
	else:
		mage_count -= 1

	palisade.set_meta(&"mage_count", mage_count)
	# Only change color if the threshold crosses 0
	if is_connected and mage_count == 1:
		get_tree().create_tween().tween_property(palisade.graphics, "self_modulate", network_tint, 0.3)
	elif mage_count <= 0:
		get_tree().create_tween().tween_property(palisade.graphics, "self_modulate", Color.WHITE, 0.3)
		

func draw_visuals(canvas: RangeIndicator) -> void:
	if not is_instance_valid(unit): return
	
	var cell_size = Island.CELL_SIZE
	var half_size = Vector2(cell_size, cell_size) / 2.0
	
	var highlighted_palisades: Array[Tower] = _connected_palisades
	if (unit as Tower).abstractive:
		highlighted_palisades = _calculate_contiguous_palisades((unit as Tower).tower_position)
	# draw a highlight on every palisade in our network
	for palisade: Tower in highlighted_palisades:
		if not is_instance_valid(palisade): continue
		
		# handle multi-tile palisades (if any exist) by iterating their footprint
		var occupied_cells = palisade.get_occupied_cells()
		
		for cell in occupied_cells:
			var pos = Island.cell_to_position(cell)
			var rect = Rect2(pos - half_size, Vector2(cell_size, cell_size))
			
			canvas.draw_rect(rect, canvas.highlight_color, false, canvas.line_width)
