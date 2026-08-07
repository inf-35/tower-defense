extends Behavior
class_name DrumRiteBehavior

@export var attacks_required: int = 4 ##unique adjacent tower attacks needed before the drum commands follow-up attacks
@export var rite_marker_effect: EffectPrototype ##hidden marker used by shared rite-affinity systems such as night lily

var _connected_neighbors: Dictionary[Tower, Callable] = {}
var _seen_attack_ids: Dictionary[int, bool] = {}
var _attack_counter: int = 0

func start() -> void:
	var tower: Tower = unit as Tower
	tower.adjacency_updated.connect(_refresh_connections)
	attach()

func detach() -> void:
	var to_remove: Array[Tower] = []
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_neighbors.keys())
	for tower: Tower in connected_towers:
		_disconnect_neighbor(tower)
		to_remove.append(tower)

	for tower: Tower in to_remove:
		_connected_neighbors.erase(tower)

	_attack_counter = 0
	_seen_attack_ids.clear()

func attach() -> void:
	_refresh_connections((unit as Tower).get_adjacent_towers())

func _refresh_connections(adj_map: Dictionary[Vector2i, Tower]) -> void:
	var current_set: Dictionary[Tower, bool] = {}
	var adjacent_towers: Array[Tower] = []
	adjacent_towers.assign(adj_map.values())

	for neighbor: Tower in adjacent_towers:
		if not is_instance_valid(neighbor):
			continue

		current_set[neighbor] = true

		if not _connected_neighbors.has(neighbor):
			var event_handler: Callable = _on_neighbor_event.bind(neighbor)
			neighbor.on_event.connect(event_handler)
			_connected_neighbors[neighbor] = event_handler
			_modify_marker_stack(neighbor, 1)
			if is_instance_valid(unit.buff_component):
				unit.buff_component.activate_new_link(neighbor)

	var to_remove: Array[Tower] = []
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_neighbors.keys())
	for old_t: Tower in connected_towers:
		if not current_set.has(old_t):
			_disconnect_neighbor(old_t)
			to_remove.append(old_t)

	for tower: Tower in to_remove:
		_connected_neighbors.erase(tower)

func _on_neighbor_event(event: GameEvent, source_neighbor: Tower) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return

	var hit_data: HitData = event.data as HitData
	if not is_instance_valid(hit_data) or not hit_data.primary:
		return

	if not HitData.consume_attack_id(hit_data, _seen_attack_ids):
		return

	_attack_counter += 1
	if _attack_counter < maxi(attacks_required, 1):
		return

	_attack_counter = 0
	if _trigger_all_except(source_neighbor, hit_data):
		unit.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _trigger_all_except(exception: Tower, parent_data: EventData) -> bool: ##arms neighboring towers so their forced follow-up attack derives from the triggering attack rather than restarting a fresh branch
	var triggered_any: bool = false
	var connected_towers: Array[Tower] = []
	connected_towers.assign(_connected_neighbors.keys())
	for tower: Tower in connected_towers:
		if tower == exception:
			continue
		if is_instance_valid(tower) and is_instance_valid(tower.attack_component):
			tower.attack_component.queue_next_attack_context(parent_data, self)
			tower.attack_component.current_cooldown = 0.0
			triggered_any = true
	return triggered_any

func _disconnect_neighbor(tower: Tower) -> void:
	if not is_instance_valid(tower):
		return
	if not _connected_neighbors.has(tower):
		return

	var event_handler: Callable = _connected_neighbors[tower]
	if tower.on_event.is_connected(event_handler):
		tower.on_event.disconnect(event_handler)
	_modify_marker_stack(tower, -1)

func _modify_marker_stack(target: Tower, amount: int) -> void:
	if not is_instance_valid(target) or not is_instance_valid(rite_marker_effect):
		return

	var effect_instance: EffectInstance = target.apply_effect(rite_marker_effect, amount)
	if is_instance_valid(effect_instance):
		effect_instance.source = unit

func draw_visuals(canvas: RangeIndicator) -> void:
	draw_visuals_adjacent_tiles(canvas)
