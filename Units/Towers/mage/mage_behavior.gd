extends Behavior
class_name MageBehavior

const NETWORK_INFLUENCE_KEY: StringName = &"mage_network"
const NETWORK_UPDATE_VISUAL_STEP_SECONDS: float = 0.05

@export var network_tint: Color = Color(0.9, 0.7, 1.0, 1.0) ##tint applied to palisades currently linked into the mage network
@export var pulse_vfx_scene: PackedScene = preload("res://Units/Towers/mage/mage_pulse.tscn") ##optional retained pulse scene for linked palisades
@export var network_damage_bonus_per_wall: float = 0.1 ##multiplicative damage bonus gained for each palisade in the connected network
@export var network_hitrate_bonus_per_wall: float = 0.1 ##multiplicative hitrate bonus gained for each palisade in the connected network
@export_range(0.0, 2.0, 0.01) var pulse_propagation_cooldown_fraction: float = 0.25 ##fraction of the modified cooldown used for the wall pulse to travel from the nearest to furthest stage
@export_range(0.0, 2.0, 0.01) var pulse_propagation_max_duration: float = 0.5 ##maximum game-time duration of one outward wall pulse

var _connected_palisades: Array[Tower] = [] ##the list of palisades this specific Mage is currently powering
var _network_rebuild_queued: bool = false
var _is_listening_for_network_events: bool = false
var _is_listening_for_island_events: bool = false
var _network_damage_modifier: Modifier
var _network_cooldown_modifier: Modifier
var _pulse_cast_id: int = 0
var _network_visual_id: int = 0

const NETWORK_EVENT_TYPES: Array[GameEvent.EventType] = [
	GameEvent.EventType.TOWER_BUILT,
	GameEvent.EventType.DIED,
	GameEvent.EventType.REPLACED,
]

func start() -> void: ##attaches the live mage network cache when this behavior first enters play
	attach()

func attach() -> void: ##subscribes to relevant tower-change events and builds the initial palisade cache
	_connect_network_events()
	_recalculate_network()

func detach() -> void: ##disconnects cache invalidation and clears the palisade visuals when the mage leaves play
	_pulse_cast_id += 1
	_disconnect_network_events()
	_disconnect_island_events()
	_network_rebuild_queued = false
	_clear_connected_palisades()

func update(_delta: float) -> void: ##pulses every connected palisade as one logical attack whenever the mage can fire
	if _is_attack_possible(false):
		_pulse_network()

func _pulse_network() -> void: ##reuses one attack context across every emitted palisade pulse in this cast
	attack_component.refresh_cooldown()
	_pulse_cast_id += 1
	var pulse_cast_id: int = _pulse_cast_id
	#pre-calculate the mage's stats (damage, range, statuses)
	#relics applied to the mage will buff these values here!
	var dmg: float = attack_component.damage
	var radius: float = attack_component.radius
	var propagation_duration: float = minf(
		attack_component.current_cooldown * pulse_propagation_cooldown_fraction,
		pulse_propagation_max_duration
	)

	#todo: visual feedback on the mage itself
	if is_instance_valid(animation_player):
		_play_animation(&"cast")

	var attack_id: int = AttackComponent.get_next_attack_id()
	var attack_context: AttackComponent.AttackLineageContext = attack_component.pull_attack_context()
	if not is_instance_valid(attack_context):
		return
	unit.play_action_squash_stretch()

	var signal_hit: HitData = attack_component.attack_data.generate_generic_hit_data()
	signal_hit.source = unit
	signal_hit.target = null
	signal_hit.target_affiliation = true
	signal_hit.damage = dmg
	signal_hit.radius = radius
	signal_hit.attack_id = attack_id
	signal_hit.negate = true
	signal_hit.primary = true
	if not attack_component.apply_attack_context(signal_hit, attack_context):
		return

	var signal_event := GameEvent.new()
	signal_event.event_type = GameEvent.EventType.PRE_HIT_DEALT
	signal_event.data = signal_hit
	signal_event.unit = unit
	unit.publish_event(signal_event)

	var mage_cell: Vector2i = (unit as Tower).tower_position
	var walls_by_distance: Dictionary[int, Array] = {}
	var pulse_distances: Array[int] = []
	for palisade: Tower in _connected_palisades:
		if not _is_active_network_wall(palisade):
			continue
		var cell_delta: Vector2i = palisade.tower_position - mage_cell
		var manhattan_distance: int = absi(cell_delta.x) + absi(cell_delta.y)
		if not walls_by_distance.has(manhattan_distance):
			walls_by_distance[manhattan_distance] = []
			pulse_distances.append(manhattan_distance)
		walls_by_distance[manhattan_distance].append(palisade)

	if pulse_distances.is_empty():
		return
	pulse_distances.sort()
	var total_steps: int = pulse_distances[-1] - pulse_distances[0]
	var stage_stagger: float = propagation_duration / float(total_steps) if total_steps > 0 else 0.0
	var previous_distance: int = pulse_distances[0]

	for stage_index: int in pulse_distances.size():
		var pulse_distance: int = pulse_distances[stage_index]
		if stage_index > 0:
			var stage_steps: int = pulse_distance - previous_distance
			await Clock.create_game_timer(stage_stagger * float(stage_steps)).timeout
		previous_distance = pulse_distance

		if pulse_cast_id != _pulse_cast_id or not is_instance_valid(unit) or unit.disabled:
			return

		for palisade: Tower in walls_by_distance[pulse_distance]:
			if not _connected_palisades.has(palisade) or not _is_active_network_wall(palisade):
				continue

			var hit_data: HitData = attack_component.attack_data.generate_generic_hit_data()
			hit_data.source = unit #mage gets credit
			hit_data.target = null #untargeted aoe
			hit_data.target_affiliation = true
			hit_data.damage = dmg
			hit_data.radius = radius
			hit_data.attack_id = attack_id
			hit_data.primary = false
			if not attack_component.apply_attack_context(hit_data, attack_context):
				continue
			palisade.play_action_squash_stretch(Vector2(0.8, 1.2), Vector2(1.03, 0.98), 0.04, 0.07)

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
func _connect_network_events() -> void: ##connects once to the global and island event buses used to invalidate palisade network caches
	if not Run.has_active_run() or not is_instance_valid(Run.player):
		return
	Run.player.subscribe_events(NETWORK_EVENT_TYPES, _on_global_event)
	_is_listening_for_network_events = true
	_connect_island_events()

func _disconnect_network_events() -> void: ##removes the global invalidation listener so ruined mages stop receiving topology events
	if Run.has_active_run() and is_instance_valid(Run.player):
		Run.player.unsubscribe_events(NETWORK_EVENT_TYPES, _on_global_event)
	_is_listening_for_network_events = false

func _connect_island_events() -> void: ##subscribes to structural island changes so blank tower death reports still rebuild the wall network
	if not is_instance_valid(Run.references):
		return
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return
	if not island.tower_changed.is_connected(_on_island_tower_changed):
		island.tower_changed.connect(_on_island_tower_changed)
	_is_listening_for_island_events = true

func _disconnect_island_events() -> void: ##removes the island structural listener without assuming the island survives teardown
	if not _is_listening_for_island_events:
		return
	if not is_instance_valid(Run.references):
		_is_listening_for_island_events = false
		return
	var island: Island = Run.references.island
	if is_instance_valid(island) and island.tower_changed.is_connected(_on_island_tower_changed):
		island.tower_changed.disconnect(_on_island_tower_changed)
	_is_listening_for_island_events = false

func _on_island_tower_changed(_tower_position: Vector2i) -> void: ##queues a rebuild after any tower build, ruin, resurrection, or removal changes grid connectivity
	if not _is_listening_for_island_events:
		return
	_queue_network_rebuild()

func _on_global_event(_unit: Unit, event: GameEvent) -> void: ##queues one cache rebuild after relevant palisade build/death/replacement events
	if not _is_listening_for_network_events:
		return
	if not _is_network_relevant_event(event):
		return
	_queue_network_rebuild()

func _is_network_relevant_event(event: GameEvent) -> bool: ##filters global events down to changes that can alter the contiguous palisade network
	if not is_instance_valid(event):
		return false

	match event.event_type:
		GameEvent.EventType.TOWER_BUILT:
			var build_data: BuildTowerData = event.data as BuildTowerData
			return is_instance_valid(build_data) and _is_network_wall(build_data.tower)
		GameEvent.EventType.DIED:
			var hit_report_data: HitReportData = event.data as HitReportData
			if not is_instance_valid(hit_report_data) or not hit_report_data.target is Tower:
				return false
			return _is_network_wall(hit_report_data.target as Tower)
		GameEvent.EventType.REPLACED:
			var replaced_data: UnitReplacedData = event.data as UnitReplacedData
			if not is_instance_valid(replaced_data):
				return false
			return _is_network_wall(replaced_data.old_unit as Tower) or _is_network_wall(replaced_data.new_unit as Tower)

	return false

func _is_network_wall(tower: Tower) -> bool: ##treats palisades as the only cache-relevant wall nodes for the mage network
	return is_instance_valid(tower) and tower.type == Towers.Type.PALISADE

func _is_active_network_wall(tower: Tower) -> bool: ##requires palisades to still be active before they can bridge or emit mage pulses
	return _is_network_wall(tower) and not tower.disabled and tower.current_state == Tower.State.ACTIVE

func _queue_network_rebuild() -> void: ##coalesces repeated same-frame wall events into one palisade flood-fill
	if _network_rebuild_queued:
		return
	_network_rebuild_queued = true
	call_deferred("_flush_network_rebuild")

func _flush_network_rebuild() -> void: ##runs the deferred cache rebuild only while the mage is still active
	_network_rebuild_queued = false
	if not _can_rebuild_network():
		return
	_recalculate_network()

func _can_rebuild_network() -> bool: ##guards deferred rebuilds that may arrive after the mage was ruined or freed
	if not is_instance_valid(unit):
		return false
	if unit.abstractive or unit.disabled:
		return false
	if not Run.is_run_ready() or not is_instance_valid(Run.references.island):
		return false
	return true

func _recalculate_network() -> void: ##diffs the new contiguous palisade set against the cached one and updates the tint state
	if not _can_rebuild_network():
		_clear_connected_palisades()
		return
	var new_network: Array[Tower] = _calculate_contiguous_palisades((unit as Tower).tower_position)
	var network_changed: bool = new_network.size() != _connected_palisades.size()
	if not network_changed:
		for palisade: Tower in new_network:
			if not _connected_palisades.has(palisade):
				network_changed = true
				break
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
	_refresh_network_stat_modifiers(_connected_palisades.size())
	if network_changed:
		if _connected_palisades.is_empty():
			_network_visual_id += 1
		else:
			_play_network_buff_visuals()

func _clear_connected_palisades() -> void: ##removes this mage's contribution from every currently cached palisade
	_network_visual_id += 1
	for palisade: Tower in _connected_palisades:
		_set_palisade_tint(palisade, false)
	_connected_palisades.clear()
	_clear_network_stat_modifiers()

func _play_network_buff_visuals() -> void: ##replays the linked-wall buff outward from the mage at a fixed delay per Manhattan step
	_network_visual_id += 1
	var network_visual_id: int = _network_visual_id
	var mage_cell: Vector2i = (unit as Tower).tower_position
	var walls_by_distance: Dictionary[int, Array] = {}
	var visual_distances: Array[int] = []

	for palisade: Tower in _connected_palisades:
		if not _is_active_network_wall(palisade):
			continue
		var cell_delta: Vector2i = palisade.tower_position - mage_cell
		var manhattan_distance: int = absi(cell_delta.x) + absi(cell_delta.y)
		if not walls_by_distance.has(manhattan_distance):
			walls_by_distance[manhattan_distance] = []
			visual_distances.append(manhattan_distance)
		walls_by_distance[manhattan_distance].append(palisade)

	if visual_distances.is_empty():
		return
	visual_distances.sort()
	var previous_distance: int = visual_distances[0]
	for stage_index: int in visual_distances.size():
		var visual_distance: int = visual_distances[stage_index]
		if stage_index > 0:
			var stage_steps: int = visual_distance - previous_distance
			await Clock.create_game_timer(NETWORK_UPDATE_VISUAL_STEP_SECONDS * float(stage_steps)).timeout
		previous_distance = visual_distance

		if network_visual_id != _network_visual_id or not is_instance_valid(unit) or unit.disabled:
			return

		for palisade: Tower in walls_by_distance[visual_distance]:
			if not _connected_palisades.has(palisade) or not _is_active_network_wall(palisade):
				continue
			palisade.play_action_squash_stretch(Vector2(0.7, 1.3), Vector2(1.3, 0.7), 0.04, 0.07)
			palisade.pulse_tint_layer(
				TintService.LAYER_RITE_PULSE,
				BuffComponent.ACTIVATION_OVERLAY_COLOR,
				BuffComponent.ACTIVATION_OVERLAY_PEAK_STRENGTH,
				BuffComponent.ACTIVATION_RAMP_IN_DURATION,
				BuffComponent.ACTIVATION_FADE_OUT_DURATION,
				false,
				Tween.TRANS_QUAD,
				Tween.EASE_OUT,
				true
			)

func _refresh_network_stat_modifiers(wall_count: int) -> void: ##updates the mage's self-buffs from the current connected wall count
	if not is_instance_valid(modifiers_component):
		return
	if wall_count <= 0:
		_clear_network_stat_modifiers()
		return

	var damage_multiplier: float = 1.0 + network_damage_bonus_per_wall * float(wall_count)
	var cooldown_multiplier: float = 1.0 / (1.0 + network_hitrate_bonus_per_wall * float(wall_count))
	_network_damage_modifier = _upsert_network_modifier(_network_damage_modifier, Attributes.id.DAMAGE, damage_multiplier)
	_network_cooldown_modifier = _upsert_network_modifier(_network_cooldown_modifier, Attributes.id.COOLDOWN, cooldown_multiplier)

func _upsert_network_modifier(existing_modifier: Modifier, attribute: Attributes.id, multiplicative: float) -> Modifier: ##creates or refreshes one behavior-owned network stat modifier
	if not is_instance_valid(existing_modifier):
		var modifier := Modifier.new(attribute, multiplicative, 0.0, -1.0, null, unit.unit_id)
		modifiers_component.add_modifier(modifier)
		return modifier

	existing_modifier.multiplicative = multiplicative
	modifiers_component.change_modifier(existing_modifier)
	return existing_modifier

func _clear_network_stat_modifiers() -> void: ##removes mage network self-buffs when the network disappears or the behavior detaches
	if not is_instance_valid(modifiers_component):
		_network_damage_modifier = null
		_network_cooldown_modifier = null
		return

	if is_instance_valid(_network_damage_modifier):
		modifiers_component.remove_modifier(_network_damage_modifier)
	if is_instance_valid(_network_cooldown_modifier):
		modifiers_component.remove_modifier(_network_cooldown_modifier)
	_network_damage_modifier = null
	_network_cooldown_modifier = null

func _calculate_contiguous_palisades(start_cell: Vector2i) -> Array[Tower]: ##flood-fills outward through linked palisades so the mage can pulse the full contiguous network
	var island = Run.references.island
	if not is_instance_valid(island): return []
	if not is_instance_valid(unit): return []
	if unit.disabled and not unit.abstractive: return []

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
		if curr_cell == start_cell or _is_active_network_wall(t):
			if _is_active_network_wall(t):
				#prevent duplicate adds for multi-tile palisades
				if not network.has(t):
					network.append(t)

			#queue neighbors
			for adj_cell in t.get_adjacent_cells():
				if not visited_cells.has(adj_cell):
					queue.append(adj_cell)

	return network

func _set_palisade_tint(palisade: Tower, is_connected: bool) -> void: ##increments or decrements the shared mage tint count on one palisade
	if not is_instance_valid(palisade) or not is_instance_valid(palisade.graphics): return

	#track how many mages are connected
	var mage_count: int = palisade.get_meta(&"mage_count", 0)

	if is_connected:
		mage_count += 1
	else:
		mage_count = maxi(mage_count - 1, 0)

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
		if palisade.has_meta("mage_pulse_vfx"):
			var pulse: RadialPulseVFX = palisade.get_meta("mage_pulse_vfx") as RadialPulseVFX
			if is_instance_valid(pulse):
				pulse.queue_free()
			palisade.remove_meta("mage_pulse_vfx")


func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the connected wall network as visual-only relationship cells
	if not is_instance_valid(unit) or not unit is Tower:
		return []
	var highlighted_palisades: Array[Tower] = _connected_palisades
	if (unit as Tower).abstractive:
		highlighted_palisades = _calculate_contiguous_palisades((unit as Tower).tower_position)
	var cells: Array[Vector2i] = []
	for palisade: Tower in highlighted_palisades:
		if not is_instance_valid(palisade):
			continue
		cells.append_array(palisade.get_occupied_cells())
	if cells.is_empty():
		return []
	return [TowerInfluence.for_cells(
		NETWORK_INFLUENCE_KEY,
		TowerInfluence.Kind.LINK,
		cells,
		null,
		[],
		false,
		TowerInfluence.Scope.WORLD,
		TowerInfluence.VisualRole.HIGHLIGHT
	)]
