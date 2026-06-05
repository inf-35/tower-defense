extends Behavior
class_name SacrificeRiteBehavior

@export var buff_icon: Texture2D
@export var buff_modifier: ModifierDataPrototype 
@export var query_kind: TowerTopologyService.QueryKind = TowerTopologyService.QueryKind.CARDINAL_RING
@export var max_range: int = 2
@export_flags("Up", "Right", "Down", "Left") var active_directions: int = 0b1111

var _subscription_id: int = -1
var _tracked_towers: Array[Tower] = []
var _wave_buffs: Array[Dictionary] = []
var _last_report: TowerTopologyService.Report = null

func start() -> void:
	if not buff_modifier:
		push_warning("SacrificeRiteBehavior: missing buff_modifier!")
		
	Phases.wave_ended.connect(_on_wave_ended)
	_subscribe()

func _make_query() -> TowerTopologyService.Query:
	return TowerTopologyService.Query.new(
		query_kind,
		1, # min range (don't include self)
		max_range,
		active_directions,
		[],
		TowerTopologyService.AxisSpace.WORLD
	)

func _subscribe() -> void:
	if _subscription_id != -1 or not is_instance_valid(References.island) or not is_instance_valid(References.island.topology_service):
		return
		
	_subscription_id = References.island.topology_service.subscribe(
		self, 
		unit as Tower, 
		_make_query(), 
		_on_topology_updated, 
		true # emit immediately to catch already existing towers
	)

# handles the clean diffing provided by the topology service
func _on_topology_updated(report: TowerTopologyService.Report) -> void:
	_last_report = report
	var new_tracked: Array[Tower] = []
	
	for t: Tower in report.unique_towers:
		# double check it's not us, and not void
		if t != unit and t.type != Towers.Type.VOID:
			new_tracked.append(t)
			
	# disconnect lost neighbors
	var to_remove: Array[Tower] = []
	for old_t: Tower in _tracked_towers:
		if not new_tracked.has(old_t):
			if is_instance_valid(old_t) and old_t.on_event.is_connected(_on_target_hit):
				old_t.on_event.disconnect(_on_target_hit)
			to_remove.append(old_t)
			
	# connect new neighbors
	for new_t: Tower in new_tracked:
		if not _tracked_towers.has(new_t):
			new_t.on_event.connect(_on_target_hit.bind(new_t))
			
	_tracked_towers = new_tracked

# reaction logic
func _on_target_hit(event: GameEvent, victim: Tower) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return
		
	var hit := event.data as HitData
	if not hit or hit.damage <= 0.0:
		return 
		
	# filter out the victim to find valid buff recipients
	var valid_targets: Array[Tower] = []
	for t: Tower in _tracked_towers:
		if is_instance_valid(t) and t != victim and is_instance_valid(t.modifiers_component):
			valid_targets.append(t)
			
	if valid_targets.is_empty():
		return
		
	# pick random target and apply stackable temporary buff
	var chosen: Tower = valid_targets.pick_random()
	var mod: Modifier = buff_modifier.generate_modifier()
	mod.cooldown = -1.0 # managed manually via wave ends
	chosen.modifiers_component.add_modifier(mod)
	UI.floating_text_manager.show_icon(buff_icon, chosen.global_position)
	
	_wave_buffs.append({ "tower": chosen, "modifier": mod })
	
	## visual feedback
	#VFXManager.play_vfx(ID.Particles.BUFF_SPARKS, chosen.global_position, Vector2.UP)

func _on_wave_ended(_wave: int) -> void:
	# clean up all accumulated buffs at the end of the wave
	for entry: Dictionary in _wave_buffs:
		var t: Tower = entry["tower"]
		var mod: Modifier = entry["modifier"]
		if is_instance_valid(t) and is_instance_valid(t.modifiers_component):
			t.modifiers_component.remove_modifier(mod)
	_wave_buffs.clear()

func _exit_tree() -> void:
	# unsubscribe from topology
	if _subscription_id != -1 and is_instance_valid(References.island) and is_instance_valid(References.island.topology_service):
		References.island.topology_service.unsubscribe(self, _subscription_id)
		_subscription_id = -1
		
	# wipe buffs and listeners
	_on_wave_ended(0) 
	for t: Tower in _tracked_towers:
		if is_instance_valid(t) and t.on_event.is_connected(_on_target_hit):
			t.on_event.disconnect(_on_target_hit)
	_tracked_towers.clear()

# visualizer hooks
func draw_visuals(canvas: RangeIndicator) -> void:
	var report: TowerTopologyService.Report = _last_report
	
	# if we don't have a report (e.g. ghost preview mode), run a one-off query
	if report == null and is_instance_valid(unit) and is_instance_valid(References.island) and is_instance_valid(References.island.topology_service):
		report = References.island.topology_service.query(unit as Tower, _make_query())
		
	if report == null:
		return

	# draw highlights for all cells covered by the query, identical to the pattern amplifier style
	var margin: int = 2
	var cell_size: float = Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5
	
	for cell: Vector2i in report.cells.values():
		var rect := Rect2(Island.cell_to_position(cell) - half_size, Vector2(cell_size, cell_size))
		# drawing a light border around the affected topology area
		canvas.draw_rect(rect, canvas.highlight_color, false, 1.0)
