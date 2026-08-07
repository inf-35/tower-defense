extends Behavior
class_name SiphonBehavior
@export var buff_modifiers: Array[ModifierDataPrototype] = [] ##modifiers applied once per siphoned enemy
@export var icon: Texture2D ##icon shown when a stack is gained

var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null

var _current_target: Tower = null
var _current_stacks: int = 0
var _active_modifiers: Array[Modifier] = []

func start() -> void:
	if buff_modifiers.is_empty():
		push_warning("Siphon behavior: no buff modifiers assigned!")

	Run.player.on_event.connect(_on_global_event)
	Run.phases.wave_ended.connect(_on_wave_ended)

	_subscribe()

func update(_d: float) -> void:
	pass

func _subscribe() -> void: ##subscribes to the single forward tower relation
	if _subscription_id != -1 or not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	_subscription_id = Run.references.island.topology_service.subscribe(self, unit as Tower, _make_query(), _on_topology_updated, true)

func _make_query() -> TowerTopologyService.Query: ##returns the directional topology query for the tower being siphoned into
	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.AXIAL_LINE,
		1,
		1,
		TowerTopologyService.AXIS_UP,
		[],
		TowerTopologyService.AxisSpace.LOCAL_FACING
	)

func _unsubscribe() -> void: ##unsubscribes without assuming the run is still fully alive
	if _subscription_id == -1 or not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	Run.references.island.topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1

func _on_topology_updated(report: TowerTopologyService.Report) -> void: ##retargets the active stack buffs when the forward tower changes
	_last_report = report

	var new_target: Tower = null
	if not report.unique_towers.is_empty():
		new_target = report.unique_towers[0]

	if new_target != _current_target:
		_clear_buffs_from_target()
		_current_target = new_target

		if is_instance_valid(unit.buff_component) and is_instance_valid(_current_target):
			unit.buff_component.activate_new_link(_current_target)

		if is_instance_valid(_current_target) and _current_stacks > 0:
			for i in range(_current_stacks):
				_apply_buff_set()

func _on_global_event(_event_unit: Unit, event: GameEvent) -> void: ##harvests enemy deaths inside the siphon collection radius
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dead_unit: Unit = event.unit
	if not is_instance_valid(dead_unit) or not dead_unit.hostile:
		return

	if not is_instance_valid(attack_component) or not attack_component.attack_data:
		return

	var radius: float = attack_component.range
	var dist_sq: float = dead_unit.global_position.distance_squared_to(unit.global_position)

	if dist_sq <= radius * radius:
		_on_unit_siphoned(dead_unit)

func _on_unit_siphoned(_dead_unit: Unit) -> void: ##adds one wave-local buff stack after a nearby enemy death
	_current_stacks += 1
	unit.play_action_squash_stretch()

	if is_instance_valid(_current_target):
		_apply_buff_set()

func _apply_buff_set() -> void: ##applies one full configured stack set to the current target
	if not is_instance_valid(_current_target) or not is_instance_valid(_current_target.modifiers_component):
		return

	for proto: ModifierDataPrototype in buff_modifiers:
		var mod: Modifier = proto.generate_modifier()
		mod.cooldown = -1.0
		_current_target.modifiers_component.add_modifier(mod)
		_active_modifiers.append(mod)

	UI.floating_text_manager.show_icon(icon, _current_target.global_position)

func _clear_buffs_from_target() -> void: ##removes every stack currently owned by this siphon
	if is_instance_valid(_current_target) and is_instance_valid(_current_target.modifiers_component):
		for mod in _active_modifiers:
			_current_target.modifiers_component.remove_modifier(mod)
	_active_modifiers.clear()

func _on_wave_ended(_wave: int) -> void: ##clears wave-local stacks when combat ends
	_clear_buffs_from_target()
	_current_stacks = 0

func _exit_tree() -> void:
	_disconnect_runtime_signals()
	_unsubscribe()
	_clear_buffs_from_target()

func _disconnect_runtime_signals() -> void: ##removes run-owned signal hooks before this tower disappears
	if is_instance_valid(Run.player) and Run.player.on_event.is_connected(_on_global_event):
		Run.player.on_event.disconnect(_on_global_event)

	if is_instance_valid(Run.phases) and Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.disconnect(_on_wave_ended)

func draw_visuals(canvas: RangeIndicator) -> void:
	var report: TowerTopologyService.Report = _last_report
	if report == null and is_instance_valid(unit) and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(unit as Tower, _make_query())

	if report == null:
		return

	for cell: Vector2i in report.cells.values():
		canvas.draw_cell(cell, canvas.highlight_color)

	if is_instance_valid(attack_component) and attack_component.attack_data:
		var radius: float = attack_component.range
		var radius_color: Color = canvas.range_color
		radius_color.a *= 0.8
		canvas.preview_circle(unit.global_position, radius, radius_color, false, canvas.line_width)
