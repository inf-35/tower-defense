extends DefaultTowerBehavior
class_name PlantTowerBehavior

const NETWORK_INFLUENCE_KEY: StringName = &"plant_forest_network"
const NETWORK_MEMBER_TYPES: Array[Towers.Type] = [Towers.Type.PLANT, Towers.Type.PLANT_UPGRADE_1, Towers.Type.FOREST]

@export var network_hitrate_bonus_per_member: float = 0.15 ##flat attacks per second gained for each other connected plant or forest

var _network_members: Array[Tower] = []
var _network_modifier: Modifier
var _network_island_ref: WeakRef
var _network_attached: bool = false
var _network_rebuild_queued: bool = false

func start() -> void: ##keeps ordinary attack behavior while owning the plant's network bonus locally
	super.start()
	attach()

func attach() -> void: ##invalidates the whole network on board changes and reconciles once save restoration completes
	if _network_attached or not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return
	_network_attached = true
	var island: Island = Run.references.island
	_network_island_ref = weakref(island)
	island.island_changed.connect(_queue_network_rebuild)
	if not Run.is_run_ready() and not Run.references_ready.is_connected(_queue_network_rebuild):
		Run.references_ready.connect(_queue_network_rebuild, CONNECT_ONE_SHOT)
	_queue_network_rebuild()

func detach() -> void: ##revokes this plant's modifier and disconnects from the actual island that owned it
	_network_attached = false
	var island: Island = _network_island_ref.get_ref() as Island if _network_island_ref != null else null
	if is_instance_valid(island) and island.island_changed.is_connected(_queue_network_rebuild):
		island.island_changed.disconnect(_queue_network_rebuild)
	_network_island_ref = null
	if Run.references_ready.is_connected(_queue_network_rebuild):
		Run.references_ready.disconnect(_queue_network_rebuild)
	_network_rebuild_queued = false
	_network_members.clear()
	var modifier: Modifier = _network_modifier
	_network_modifier = null
	if is_instance_valid(modifier) and is_instance_valid(modifiers_component):
		modifiers_component.remove_modifier(modifier)

func _exit_tree() -> void: ##also cleans up direct removal and run teardown
	detach()

func _queue_network_rebuild() -> void: ##coalesces board edits so graph membership and its bonus change together
	if not _network_attached or _network_rebuild_queued:
		return
	_network_rebuild_queued = true
	_rebuild_network.call_deferred()

func _rebuild_network() -> void: ##takes one graph snapshot for both the hitrate modifier and selection highlights
	_network_rebuild_queued = false
	if not _network_attached or not is_instance_valid(unit) or unit.is_queued_for_deletion() or unit.disabled:
		return
	var island: Island = _network_island_ref.get_ref() as Island if _network_island_ref != null else null
	if not Run.is_run_ready() or not is_instance_valid(island) or island != Run.references.island or island.game_ending:
		return
	var new_members: Array[Tower] = island.topology_service.get_connected_towers(unit as Tower, _is_network_member)
	var previous_members: Array[Tower] = _network_members
	_network_members = new_members
	var bonus: float = network_hitrate_bonus_per_member * float(_network_members.size())
	if bonus <= 0.0:
		var modifier: Modifier = _network_modifier
		_network_modifier = null
		if is_instance_valid(modifier):
			modifiers_component.remove_modifier(modifier)
	elif not is_instance_valid(_network_modifier):
		_network_modifier = Modifier.new(Attributes.id.ATTACK_RATE, 1.0, bonus, -1.0, null, unit.unit_id)
		modifiers_component.add_modifier(_network_modifier)
	elif not is_equal_approx(_network_modifier.additive, bonus):
		_network_modifier.additive = bonus
		modifiers_component.change_modifier(_network_modifier)
	var gained_members: bool = false
	for member: Tower in _network_members:
		if previous_members.has(member):
			continue
		gained_members = true
		BuffComponent.play_link_wisp(member, unit as Tower)
	if gained_members:
		unit.pulse_tint_layer(
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

func _is_network_member(tower: Tower) -> bool: ##only active allied plants and forests conduct or contribute to this network
	return not tower.hostile and not tower.abstractive and tower.current_state == Tower.State.ACTIVE and NETWORK_MEMBER_TYPES.has(tower.type)

func draw_visuals(canvas: RangeIndicator) -> void: ##draws the normal attack range while shared introspection owns the plant-forest network cells
	super.draw_visuals(canvas)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##describes the plant and forest towers contributing to its contiguous network
	if not is_instance_valid(unit) or not unit is Tower:
		return []
	var tower: Tower = unit as Tower
	var sources: Array[Tower] = _network_members
	if tower.abstractive and is_instance_valid(Run.references) and is_instance_valid(Run.references.island):
		sources = Run.references.island.topology_service.get_connected_towers(tower, _is_network_member)

	var cells: Array[Vector2i] = []
	for source: Tower in sources:
		if is_instance_valid(source):
			cells.append_array(source.get_occupied_cells())
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
