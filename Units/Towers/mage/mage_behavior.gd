extends Behavior
class_name MageBehavior

@export var network_tint: Color = Color(0.9, 0.7, 1.0, 1.0) ##tint applied to palisades currently linked into the mage network
@export var pulse_vfx_scene: PackedScene = preload("res://Units/Towers/mage/mage_pulse.tscn") ##optional retained pulse scene for linked palisades

var _connected_palisades: Array[Tower] = [] ##the list of palisades this specific Mage is currently powering

func start() -> void: ##subscribes to build and death updates so the contiguous palisade network stays current
	Run.player.on_event.connect(_on_global_event) ##listen globally for any tower changes to recalculate the contiguous network
	_recalculate_network()

func detach() -> void: ##clears the cached network and removes the visual tint when the mage leaves play
	#cleanup: if the mage is destroyed/sold, untint everything
	for p in _connected_palisades:
		_set_palisade_tint(p, false)
	_connected_palisades.clear()

func update(_delta: float) -> void: ##pulses every connected palisade as one logical attack whenever the mage can fire
	if _is_attack_possible(false):
		_pulse_network()

func _pulse_network() -> void: ##reuses one attack context across every emitted palisade pulse in this cast
	attack_component.refresh_cooldown()
	#pre-calculate the mage's stats (damage, range, statuses)
	#relics applied to the mage will buff these values here!
	var dmg: float = attack_component.damage
	var radius: float = attack_component.radius

	#todo: visual feedback on the mage itself
	if is_instance_valid(animation_player):
		_play_animation(&"cast")

	var attack_id: int = AttackComponent.get_next_attack_id()
	var attack_context: AttackComponent.AttackLineageContext = attack_component.pull_attack_context()
	if not is_instance_valid(attack_context):
		return
	unit.play_action_squash_stretch()

	#command connected palisades to attack
	for palisade: Tower in _connected_palisades:
		if not is_instance_valid(palisade): continue

		var hit_data: HitData = attack_component.attack_data.generate_generic_hit_data()
		hit_data.source = unit #mage gets credit
		hit_data.target = null #untargeted aoe
		hit_data.target_affiliation = true
		hit_data.damage = dmg
		hit_data.radius = radius
		hit_data.attack_id = attack_id
		if not attack_component.apply_attack_context(hit_data, attack_context):
			continue

		var delivery := DeliveryData.new()
		delivery.delivery_method = DeliveryData.DeliveryMethod.CONE_AOE
		delivery.use_source_position_override = true
		delivery.source_position = palisade.global_position
		delivery.cone_angle = 360.0

		unit.deal_hit(hit_data, delivery)

		#trigger the retained vfx
		if palisade.has_meta("mage_pulse_vfx"):
			var pulse = palisade.get_meta("mage_pulse_vfx") as RadialPulseVFX
			if is_instance_valid(pulse):
				pulse.start_radius = radius * 0.75
				pulse.max_radius = radius #update dynamically in case relics buffed range
				pulse.reset()
				pulse.start()
		#play the VFX defined in the Mage's attack data on the palisade
		if hit_data.vfx_on_spawn:
			VFXManager.play_vfx(hit_data.vfx_on_spawn, palisade.global_position, Vector2.UP)

#network management
func _on_global_event(_unit: Unit, event: GameEvent) -> void: ##rebuilds the network when palisade topology changes
	if event.event_type == GameEvent.EventType.TOWER_BUILT or event.event_type == GameEvent.EventType.DIED or event.event_type == GameEvent.EventType.REPLACED:
		if event.event_type == GameEvent.EventType.TOWER_BUILT and (event.data as BuildTowerData).tower.type != Towers.Type.PALISADE:
			return
		if event.event_type == GameEvent.EventType.DIED and (event.data as HitReportData).target is Tower and ((event.data as HitReportData).target as Tower).type != Towers.Type.PALISADE:
			return
		_recalculate_network.call_deferred()

func _recalculate_network() -> void: ##diffs the new contiguous palisade set against the cached one and updates the tint state
	if  unit.abstractive: return
	var new_network: Array[Tower] = _calculate_contiguous_palisades((unit as Tower).tower_position)
	#--- apply diff for tinting ---

	#1. remove tint from disconnected palisades
	for old_p: Tower in _connected_palisades:
		if is_instance_valid(old_p) and not new_network.has(old_p):
			_set_palisade_tint(old_p, false)

	#2. add tint to newly connected palisades
	for new_p: Tower in new_network:
		if not _connected_palisades.has(new_p):
			_set_palisade_tint(new_p, true)

	_connected_palisades = new_network

func _calculate_contiguous_palisades(start_cell: Vector2i) -> Array[Tower]: ##flood-fills outward through linked palisades so the mage can pulse the full contiguous network
	var island = Run.references.island
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

		#valid nodes: the starting cell (which might be empty ground in preview), or palisades
		if curr_cell == start_cell or (t.type == Towers.Type.PALISADE and not t.disabled):
			if t.type == Towers.Type.PALISADE and not t.disabled:
				#prevent duplicate adds for multi-tile palisades
				if not network.has(t):
					network.append(t)

			#queue neighbors
			for adj_cell in t.get_adjacent_cells():
				if not visited_cells.has(adj_cell):
					queue.append(adj_cell)

	return network

func _set_palisade_tint(palisade: Tower, is_connected: bool) -> void:
	if not is_instance_valid(palisade) or not is_instance_valid(palisade.graphics): return

	#track how many mages are connected
	var mage_count: int = palisade.get_meta(&"mage_count", 0)

	if is_connected:
		mage_count += 1
	else:
		mage_count -= 1

	palisade.set_meta(&"mage_count", mage_count)
	#only change color if the threshold crosses 0
	if is_connected and mage_count == 1:
		get_tree().create_tween().tween_property(palisade.graphics, "self_modulate", network_tint, 0.3)
		if pulse_vfx_scene:
			var pulse: RadialPulseVFX = pulse_vfx_scene.instantiate() as RadialPulseVFX
			pulse.autostart = false
			pulse.destroy_on_finish = false
			#add to palisade so it moves with it and stays clean
			palisade.add_child(pulse)
			palisade.set_meta("mage_pulse_vfx", pulse)
	elif mage_count <= 0:
		get_tree().create_tween().tween_property(palisade.graphics, "self_modulate", Color.WHITE, 0.3)


func draw_visuals(canvas: RangeIndicator) -> void:
	if not is_instance_valid(unit): return

	var cell_size = Island.CELL_SIZE
	var half_size: Vector2 = Vector2(cell_size, cell_size) / 2.0

	var highlighted_palisades: Array[Tower] = _connected_palisades
	if (unit as Tower).abstractive:
		highlighted_palisades = _calculate_contiguous_palisades((unit as Tower).tower_position)
	#draw a highlight on every palisade in our network
	for palisade: Tower in highlighted_palisades:
		if not is_instance_valid(palisade): continue

		#handle multi-tile palisades (if any exist) by iterating their footprint
		var occupied_cells = palisade.get_occupied_cells()

		for cell in occupied_cells:
			var pos = Island.cell_to_position(cell)
			var rect: Rect2 = Rect2(pos - half_size, Vector2(cell_size, cell_size))

			canvas.preview_rect(rect, canvas.highlight_color, false, canvas.line_width)
