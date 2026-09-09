extends Behavior
class_name CommandPostBehavior

const INPUT_INFLUENCE_KEY: StringName = &"outpost_inputs"
const OUTPUT_INFLUENCE_KEY: StringName = &"outpost_output"

@export var suppression_modifier: ModifierDataPrototype
@export var attacks_required: int = 1
@export var max_commands_per_second: float = 3.0 ##maximum times this outpost can command its target each second
@export var command_beam_vfx: VFXInfo ##authored pulse beam settings used when this outpost forces its linked tower to attack
@export var passive_beam_strength: float = 0.33 ##scales the continuous beam so the passive link reads softly behind command pulses
@export var icon: Texture2D ##icon shown when the outpost commands its target tower

var _target_tower: Tower = null
var _target_suppression_modifier: Modifier
var _passive_beam_vfx: SwirlLineVFX = null
var _my_neighbors: Dictionary[Tower, bool] = {}
var _attack_counter: int = 0
var _seen_attack_ids: Dictionary[int, bool] = {} ##int: attack id, bool: true once this outpost has counted that source attack
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
	set_process(true)
	_recalculate_target()

func detach() -> void:
	_release_target()
	clear_tower_influences()
	_seen_attack_ids.clear()
	_can_command = true
	_command_limit_token += 1
	_last_trigger_hit = null

func _process(_delta: float) -> void:
	_refresh_passive_beam()

func _on_my_adjacency_updated(adj_map: Dictionary) -> void:
	var tower: Tower = unit as Tower
	var back_direction: Vector2i = -tower.get_forward_direction()
	var current_neighbors: Dictionary[Tower, bool] = {}

	for offset: Vector2i in adj_map:
		var neighbor: Tower = adj_map[offset]
		if not is_instance_valid(neighbor) or neighbor == unit or neighbor == _target_tower:
			continue
		if Tower.get_side_from_offset(tower.size, offset) != Tower.get_side_from_offset(tower.size, back_direction):
			continue
		current_neighbors[neighbor] = true
		if not _my_neighbors.has(neighbor):
			neighbor.subscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_neighbor_event)

	var to_remove: Array[Tower] = []
	for old_neighbor: Tower in _my_neighbors:
		if current_neighbors.has(old_neighbor):
			continue
		if is_instance_valid(old_neighbor):
			old_neighbor.unsubscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_neighbor_event)
		to_remove.append(old_neighbor)

	for old_neighbor: Tower in to_remove:
		_my_neighbors.erase(old_neighbor)

	_my_neighbors = current_neighbors
	sync_tower_influences()

func _on_neighbor_event(event: GameEvent) -> void: ##adds the outpost's directional bonus only to routed attacks from current neighboring towers
	var hit_data: HitData = event.data as HitData
	if not is_instance_valid(hit_data):
		return

	if not hit_data.primary:
		return

	if not HitData.consume_attack_id(hit_data, _seen_attack_ids):
		return

	_last_trigger_hit = hit_data
	_attack_counter += 1
	if _attack_counter >= attacks_required:
		_attack_counter = 0
		_command_target_to_fire()

func _recalculate_target() -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive or tower.disabled:
		_release_target()
		sync_tower_influences()
		return

	var scan: Tower.ForwardScanResult = tower.scan_forward(49)
	var found_tower: Tower = scan.hit_tower

	if found_tower != _target_tower:
		_release_target()
		if is_instance_valid(found_tower):
			_bind_target(found_tower)
	sync_tower_influences()

func _bind_target(target: Tower) -> void:
	_target_tower = target
	if is_instance_valid(_target_tower.attack_component):
		_target_tower.attack_component.current_cooldown = 10000.0
	_attack_counter = 0
	_seen_attack_ids.clear()
	_target_suppression_modifier = suppression_modifier.generate_modifier()
	target.modifiers_component.add_modifier(_target_suppression_modifier)
	if is_instance_valid(unit.buff_component):
		unit.buff_component.activate_new_link(target, false)
	_refresh_passive_beam()

func _release_target() -> void:
	if is_instance_valid(_target_tower):
		_target_tower.modifiers_component.remove_modifier(_target_suppression_modifier)
	_target_tower = null
	_last_trigger_hit = null
	_clear_passive_beam()

func _command_target_to_fire() -> void: ##forces the linked tower to fire and briefly pulses the support beam so the trigger reads in-world
	if not is_instance_valid(_target_tower) or not is_instance_valid(_target_tower.attack_component): return
	if not _can_command:
		return
	_start_command_limit()
	if is_instance_valid(_last_trigger_hit):
		_target_tower.attack_component.queue_next_attack_context(_last_trigger_hit, self)
	_target_tower.attack_component.current_cooldown = 0.0
	if is_instance_valid(unit.buff_component):
		unit.buff_component.activate_target(_target_tower, "", icon, false)
	VFXManager.play_swirl_line_info(command_beam_vfx, unit.global_position, _target_tower.global_position)

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

func _refresh_passive_beam() -> void: ##keeps a faint continuous link visible while the outpost has a valid commanded target
	if not _has_passive_beam_target():
		_clear_passive_beam()
		return

	var source_tower: Tower = unit as Tower
	var start_position: Vector2 = source_tower.global_position
	var end_position: Vector2 = _target_tower.global_position

	if not is_instance_valid(_passive_beam_vfx):
		_passive_beam_vfx = VFXManager.create_swirl_beam_info(command_beam_vfx, start_position, end_position, passive_beam_strength)
		return

	_passive_beam_vfx.set_segment(start_position, end_position)

func _has_passive_beam_target() -> bool:
	var source_tower: Tower = unit as Tower
	if not is_instance_valid(source_tower) or source_tower.disabled:
		return false
	if not is_instance_valid(_target_tower) or _target_tower.disabled:
		return false
	return is_instance_valid(command_beam_vfx) and passive_beam_strength > 0.0

func _clear_passive_beam() -> void:
	if is_instance_valid(_passive_beam_vfx):
		_passive_beam_vfx.stop()
	_passive_beam_vfx = null

func _exit_tree() -> void:
	_release_target()
	clear_tower_influences()
	for neighbor: Tower in _my_neighbors:
		if is_instance_valid(neighbor):
			neighbor.unsubscribe_event(GameEvent.EventType.PRE_HIT_DEALT, _on_neighbor_event)
	_my_neighbors.clear()

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes rear command inputs and the forward output lane through one shared spatial model
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.disabled:
		return []

	var back_direction: Vector2i = -tower.get_forward_direction()
	var input_cells: Array[Vector2i] = []
	for cell: Vector2i in tower.get_adjacent_cells():
		var offset: Vector2i = cell - tower.tower_position
		if Tower.get_side_from_offset(tower.size, offset) != Tower.get_side_from_offset(tower.size, back_direction):
			continue
		input_cells.append(cell)

	var influences: Array[TowerInfluence] = [TowerInfluence.for_cells(
		INPUT_INFLUENCE_KEY,
		TowerInfluence.Kind.INPUT,
		input_cells,
		null,
		[],
		false,
		TowerInfluence.Scope.TOWER,
		TowerInfluence.VisualRole.INPUT
	)]

	var scan: Tower.ForwardScanResult = tower.scan_forward(49)
	if scan.distance_tiles <= 0:
		return influences
	var output_cells: Array[Vector2i] = []
	var direction: Vector2i = tower.get_forward_direction()
	for distance: int in range(1, scan.distance_tiles + 1):
		output_cells.append(tower.tower_position + direction * distance)
	var accent_cells: Array[Vector2i] = []
	if is_instance_valid(scan.hit_tower):
		accent_cells.append(scan.impact_cell)
	var output_modifiers: Array[ModifierDataPrototype] = []
	if is_instance_valid(suppression_modifier):
		output_modifiers.append(suppression_modifier)
	influences.append(TowerInfluence.for_line(
		OUTPUT_INFLUENCE_KEY,
		TowerInfluence.Kind.OUTPUT,
		output_cells,
		Island.cell_to_position(tower.tower_position),
		Island.cell_to_position(scan.impact_cell),
		accent_cells,
		null,
		output_modifiers,
		false,
		TowerInfluence.Scope.TOWER,
		TowerInfluence.VisualRole.HIGHLIGHT,
		1.0 if is_instance_valid(scan.hit_tower) else 0.3,
		2.0
	))
	return influences
