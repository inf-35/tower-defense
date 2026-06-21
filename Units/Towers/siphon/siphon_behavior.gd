extends Behavior
class_name SiphonBehavior
#TODO: implement stacking modifiers as stacks of a single modifier
#instead of as applying multiple instances
#configuration
@export var buff_modifiers: Array[ModifierDataPrototype] = []
@export var icon: Texture2D

#state
var _subscription_id: int = -1
var _last_report: TowerTopologyService.Report = null

var _current_target: Tower = null
var _current_stacks: int = 0
var _active_modifiers: Array[Modifier] = []

func start() -> void:
	if buff_modifiers.is_empty():
		push_warning("Siphon behavior: no buff modifiers assigned!")
	#listen for deaths to harvest
	Run.player.on_event.connect(_on_global_event)
	#listen for wave ends to clear stacks
	Run.phases.wave_ended.connect(_on_wave_ended)

	_subscribe()

func update(_d: float) -> void:
	pass

#--- topology management ---
func _subscribe() -> void:
	if _subscription_id != -1 or not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	_subscription_id = Run.references.island.topology_service.subscribe(self, unit as Tower, _make_query(), _on_topology_updated, true)

func _make_query() -> TowerTopologyService.Query:
	#target exactly 1 tile in front of us, relative to our facing
	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.AXIAL_LINE,
		1,
		1,
		TowerTopologyService.AXIS_UP, #'up' in local space = forward
		[],
		TowerTopologyService.AxisSpace.LOCAL_FACING
	)

func _unsubscribe() -> void:
	if _subscription_id == -1 or not is_instance_valid(Run.references.island) or not is_instance_valid(Run.references.island.topology_service):
		return
	Run.references.island.topology_service.unsubscribe(self, _subscription_id)
	_subscription_id = -1

func _on_topology_updated(report: TowerTopologyService.Report) -> void:
	_last_report = report

	var new_target: Tower = null
	if not report.unique_towers.is_empty():
		new_target = report.unique_towers[0]

	#if target changed (e.g. tower sold, or upgraded to a new unit instance)
	if new_target != _current_target:
		_clear_buffs_from_target()
		_current_target = new_target

		#if we already have stacks this wave, re-apply them to the new target
		if is_instance_valid(_current_target) and _current_stacks > 0:
			for i in range(_current_stacks):
				_apply_buff_set()

#--- gameplay logic ---

func _on_global_event(event_unit: Unit, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dead_unit = event.unit
	if not is_instance_valid(dead_unit) or not dead_unit.hostile:
		return

	if not is_instance_valid(attack_component) or not attack_component.attack_data:
		return

	#check distance
	var radius := attack_component.range
	var dist_sq = dead_unit.global_position.distance_squared_to(unit.global_position)

	if dist_sq <= radius * radius:
		_on_unit_siphoned(dead_unit)

func _on_unit_siphoned(dead_unit: Unit) -> void:
	_current_stacks += 1

	#visual feedback on siphon
	#VFXManager.play_vfx(ID.Particles.BUFF_SPARKS, unit.global_position, Vector2.UP)

	if is_instance_valid(_current_target):
		_apply_buff_set()

func _apply_buff_set() -> void:
	if not is_instance_valid(_current_target) or not is_instance_valid(_current_target.modifiers_component):
		return

	#apply the entire array of configured modifiers
	for proto: ModifierDataPrototype in buff_modifiers:
		var mod: Modifier = proto.generate_modifier()
		mod.cooldown = -1.0 #managed manually via wave ends
		_current_target.modifiers_component.add_modifier(mod)
		_active_modifiers.append(mod)

	UI.floating_text_manager.show_icon(icon, _current_target.global_position)
	#visual feedback on target
	#VFXManager.play_vfx(ID.Particles.BUFF_SPARKS, _current_target.global_position, Vector2.UP)

func _clear_buffs_from_target() -> void:
	if is_instance_valid(_current_target) and is_instance_valid(_current_target.modifiers_component):
		for mod in _active_modifiers:
			_current_target.modifiers_component.remove_modifier(mod)
	_active_modifiers.clear()

func _on_wave_ended(_wave: int) -> void:
	_clear_buffs_from_target()
	_current_stacks = 0

func _exit_tree() -> void:
	_unsubscribe()
	_clear_buffs_from_target()

#--- visualizer ---

func draw_visuals(canvas: RangeIndicator) -> void:
	var report = _last_report
	if report == null and is_instance_valid(unit) and is_instance_valid(Run.references.island) and is_instance_valid(Run.references.island.topology_service):
		report = Run.references.island.topology_service.query(unit as Tower, _make_query())

	if report == null:
		return

	for cell: Vector2i in report.cells.values():
		canvas.draw_cell(cell, canvas.highlight_color)

	#2. draw the siphon collection radius
	if is_instance_valid(attack_component) and attack_component.attack_data:
		var radius = attack_component.range
		#faint circle to show where it collects from
		var radius_color = canvas.range_color
		radius_color.a *= 0.8
		canvas.preview_circle(unit.global_position, radius, radius_color, false, canvas.line_width)
