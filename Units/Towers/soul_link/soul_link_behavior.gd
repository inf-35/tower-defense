extends Behavior
class_name SoulLinkBehavior

const FORWARD_INFLUENCE_KEY: StringName = &"soul_link_forward"
const BACK_INFLUENCE_KEY: StringName = &"soul_link_back"

var _forward_tower: Tower
var _back_tower: Tower

func start() -> void:
	_connect_island_updates()
	_refresh_links()

func attach() -> void:
	_connect_island_updates()
	_refresh_links()

func detach() -> void:
	_disconnect_island_updates()
	_disconnect_forward_tower()
	_back_tower = null
	clear_tower_influences()

func _exit_tree() -> void:
	detach()

func _connect_island_updates() -> void:
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	if island.island_changed.is_connected(_refresh_links):
		return

	island.island_changed.connect(_refresh_links)

func _disconnect_island_updates() -> void:
	if not Run.references:
		return
	
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	if island.island_changed.is_connected(_refresh_links):
		island.island_changed.disconnect(_refresh_links)

func _refresh_links() -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or tower.abstractive:
		return
	sync_tower_influences()

	var forward_direction: Vector2i = tower.get_forward_direction()
	var new_forward_tower: Tower = _get_tower_at_offset(forward_direction)
	var new_back_tower: Tower = _get_tower_at_offset(-forward_direction)

	if not _is_linkable_tower(new_forward_tower):
		new_forward_tower = null

	if not _is_linkable_tower(new_back_tower):
		new_back_tower = null

	if new_forward_tower != _forward_tower:
		_disconnect_forward_tower()
		_forward_tower = new_forward_tower
		_connect_forward_tower()

	_back_tower = new_back_tower

func _get_tower_at_offset(offset: Vector2i) -> Tower:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or offset == Vector2i.ZERO:
		return null

	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return null

	return island.get_tower_on_tile(tower.tower_position + offset)

func _connect_forward_tower() -> void:
	if not is_instance_valid(_forward_tower):
		return

	if _forward_tower.is_subscribed_to_event(GameEvent.EventType.HIT_RECEIVED, _on_forward_tower_event):
		return

	_forward_tower.subscribe_event(GameEvent.EventType.HIT_RECEIVED, _on_forward_tower_event)

func _disconnect_forward_tower() -> void:
	if not is_instance_valid(_forward_tower):
		_forward_tower = null
		return

	_forward_tower.unsubscribe_event(GameEvent.EventType.HIT_RECEIVED, _on_forward_tower_event)

	_forward_tower = null

func _on_forward_tower_event(event: GameEvent) -> void: ##shares routed incoming damage from the currently linked forward tower
	if unit.disabled:
		return

	if not _is_linkable_tower(_back_tower):
		return

	var incoming_hit: HitData = event.data as HitData
	if not is_instance_valid(incoming_hit) or incoming_hit.negate:
		return

	incoming_hit.negate = true
	var transferred_hit: HitData = _create_transferred_hit(incoming_hit)
	if not is_instance_valid(transferred_hit):
		return

	unit.play_action_squash_stretch()
	_back_tower.take_hit(transferred_hit)

func _create_transferred_hit(incoming_hit: HitData) -> HitData:
	var transferred_hit: HitData = incoming_hit.duplicate() as HitData
	transferred_hit.negate = false
	transferred_hit.target = _back_tower
	transferred_hit.target_affiliation = _back_tower.hostile
	if not transferred_hit.derive_lineage_from(incoming_hit, self):
		return null
	transferred_hit.source = incoming_hit.get_source_unit()
	transferred_hit.attack_id = AttackComponent.get_next_attack_id()
	transferred_hit.primary = false
	transferred_hit.velocity = (_back_tower.global_position - _forward_tower.global_position).normalized()
	return transferred_hit

func _is_linkable_tower(candidate: Tower) -> bool:
	if not is_instance_valid(candidate):
		return false

	if candidate == unit:
		return false

	if candidate.current_state != Tower.State.ACTIVE:
		return false

	if not is_instance_valid(candidate.health_component):
		return false

	if candidate.health_component.health <= 0.0:
		return false

	return true

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the forward damage input and rear transfer output as facing-relative links
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return []

	var start_pos: Vector2 = Island.cell_to_position(tower.tower_position)
	var forward_direction: Vector2i = tower.get_forward_direction()
	var forward_cell: Vector2i = tower.tower_position + forward_direction
	var back_cell: Vector2i = tower.tower_position - forward_direction
	return [
		TowerInfluence.for_line(
			FORWARD_INFLUENCE_KEY,
			TowerInfluence.Kind.INPUT,
			[forward_cell],
			start_pos,
			Island.cell_to_position(forward_cell),
			[forward_cell],
			null,
			[],
			true,
			TowerInfluence.Scope.TOWER,
			TowerInfluence.VisualRole.POSITIVE
		),
		TowerInfluence.for_line(
			BACK_INFLUENCE_KEY,
			TowerInfluence.Kind.OUTPUT,
			[back_cell],
			start_pos,
			Island.cell_to_position(back_cell),
			[back_cell],
			null,
			[],
			true,
			TowerInfluence.Scope.TOWER,
			TowerInfluence.VisualRole.NEGATIVE
		),
	]
