extends Behavior
class_name CommandPostBehavior

@export var suppression_modifier: ModifierDataPrototype
@export var attacks_required: int = 1
@export var max_commands_per_second: float = 3.0

var _target_tower: Tower = null
var _target_suppression_modifier: Modifier
var _my_neighbors: Dictionary[Tower, bool] = {}
var _attack_counter: int = 0
var _seen_attack_ids: Dictionary[int, bool] = {}
var _can_command: bool = true
var _command_limit_token: int = 0
var _last_trigger_hit: HitData

func start() -> void:
	if not suppression_modifier:
		push_warning("CommandPost: Missing suppression_modifier!")

	var tower: Tower = unit as Tower

	tower.adjacency_updated.connect(_on_my_adjacency_updated)
	_on_my_adjacency_updated(tower.get_adjacent_towers())

	Run.references.island.island_changed.connect(_recalculate_target)
	_recalculate_target()

func detach() -> void:
	_release_target()
	_seen_attack_ids.clear()
	_can_command = true
	_command_limit_token += 1
	_last_trigger_hit = null

func _on_my_adjacency_updated(adj_map: Dictionary) -> void:
	var current_neighbors: Dictionary[Tower, bool] = {}

	for n: Tower in adj_map.values():
		if is_instance_valid(n) and n != unit and n != _target_tower:
			current_neighbors[n] = true
			if not _my_neighbors.has(n):
				n.on_event.connect(_on_neighbor_event.bind(n))

	var to_remove: Array[Tower] = []
	for old_n: Tower in _my_neighbors:
		if not current_neighbors.has(old_n):
			if is_instance_valid(old_n) and old_n.on_event.is_connected(_on_neighbor_event):
				old_n.on_event.disconnect(_on_neighbor_event)
			to_remove.append(old_n)

	for n: Tower in to_remove:
		_my_neighbors.erase(n)

	_my_neighbors = current_neighbors

func _on_neighbor_event(event: GameEvent, _source: Tower) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT: return

	var hit_data: HitData = event.data as HitData
	if not HitData.consume_attack_id(hit_data, _seen_attack_ids):
		return

	_last_trigger_hit = hit_data
	_attack_counter += 1
	if _attack_counter >= attacks_required:
		_attack_counter = 0
		_command_target_to_fire()

func _recalculate_target() -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled: return

	var scan: Tower.ForwardScanResult = tower.scan_forward(49)
	var found_tower: Tower = scan.hit_tower

	if found_tower != _target_tower:
		_release_target()
		if is_instance_valid(found_tower):
			_bind_target(found_tower)

func _bind_target(target: Tower) -> void:
	_target_tower = target
	if is_instance_valid(_target_tower.attack_component):
		_target_tower.attack_component.current_cooldown = 10000.0
	_attack_counter = 0
	_seen_attack_ids.clear()
	_target_suppression_modifier = suppression_modifier.generate_modifier()
	target.modifiers_component.add_modifier(_target_suppression_modifier)

func _release_target() -> void:
	if is_instance_valid(_target_tower):
		_target_tower.modifiers_component.remove_modifier(_target_suppression_modifier)
	_target_tower = null
	_last_trigger_hit = null

func _command_target_to_fire() -> void:
	if not is_instance_valid(_target_tower) or not is_instance_valid(_target_tower.attack_component): return
	if not _can_command:
		return
	_start_command_limit()
	if is_instance_valid(_last_trigger_hit):
		_target_tower.attack_component.queue_next_attack_context(_last_trigger_hit, self)
	_target_tower.attack_component.current_cooldown = 0.0

	if is_instance_valid(animation_player):
		_play_animation(&"cast")

func _start_command_limit() -> void:
	if max_commands_per_second <= 0.0:
		return

	_command_limit_token += 1
	var token: int = _command_limit_token
	_can_command = false
	await Clock.await_game_time(1.0 / max_commands_per_second)
	if token != _command_limit_token or not is_inside_tree():
		return
	_can_command = true

func _exit_tree() -> void:
	_release_target()
	for n: Tower in _my_neighbors:
		if is_instance_valid(n) and n.on_event.is_connected(_on_neighbor_event):
			n.on_event.disconnect(_on_neighbor_event)
	_my_neighbors.clear()

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower): return

	var neighbors: Array[Vector2i] = tower.get_adjacent_cells()
	for n: Vector2i in neighbors:
		var fade_color: Color = canvas.highlight_color
		fade_color.a *= 0.5
		canvas.draw_cell(n, fade_color)

	var scan: Tower.ForwardScanResult = tower.scan_forward(20)
	var target: Tower = scan.hit_tower
	var start_pos: Vector2 = Island.cell_to_position(tower.tower_position)
	if is_instance_valid(target):
		var end_pos: Vector2 = Island.cell_to_position(scan.impact_cell)
		canvas.draw_line(start_pos, end_pos, canvas.highlight_color, 2.0)
		canvas.draw_cell(scan.impact_cell, canvas.highlight_color)
	else:
		var end_pos: Vector2 = Island.cell_to_position(scan.last_valid_cell)
		var fade_color: Color = canvas.highlight_color
		fade_color.a *= 0.3
		canvas.draw_line(start_pos, end_pos, fade_color, 2.0)
