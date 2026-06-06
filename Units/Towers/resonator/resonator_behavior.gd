extends Behavior
class_name ResonatorBehavior

#configuration
@export var cooldown_advance_percent: float = 0.10 ##0.10 = advance by 10% of max cooldown
@export var icon: Texture2D

#--- state ---
var _front_subscription_id: int = -1
var _back_subscription_id: int = -1

var _trigger_tower: Tower = null
var _receiver_tower: Tower = null

var _last_front_report: TowerTopologyService.Report = null
var _last_back_report: TowerTopologyService.Report = null

func start() -> void:
	_subscribe()

#--- topology management ---

func _make_query(is_front: bool) -> TowerTopologyService.Query:
	#front = axis_up, back = axis_down (in local space)
	var axis = TowerTopologyService.AXIS_UP if is_front else TowerTopologyService.AXIS_DOWN

	return TowerTopologyService.Query.new(
		TowerTopologyService.QueryKind.AXIAL_LINE,
		1,
		1,
		axis,
		[],
		TowerTopologyService.AxisSpace.LOCAL_FACING
	)

func _subscribe() -> void:
	var topo = Run.references.island.topology_service if is_instance_valid(Run.references.island) else null
	if not topo: return

	_front_subscription_id = topo.subscribe(self, unit as Tower, _make_query(true), _on_front_updated, true)
	_back_subscription_id = topo.subscribe(self, unit as Tower, _make_query(false), _on_back_updated, true)

func _unsubscribe() -> void:
	var topo = Run.references.island.topology_service if is_instance_valid(Run.references.island) else null
	if not topo: return

	if _front_subscription_id != -1:
		topo.unsubscribe(self, _front_subscription_id)
		_front_subscription_id = -1

	if _back_subscription_id != -1:
		topo.unsubscribe(self, _back_subscription_id)
		_back_subscription_id = -1

#--- connection logic ---

func _on_front_updated(report: TowerTopologyService.Report) -> void:
	_last_front_report = report

	var new_trigger: Tower = null
	if not report.unique_towers.is_empty():
		new_trigger = report.unique_towers[0]

	#manage subscription to the front tower
	if _trigger_tower != new_trigger:
		#disconnect old
		if is_instance_valid(_trigger_tower):
			if _trigger_tower.on_event.is_connected(_on_trigger_tower_event):
				_trigger_tower.on_event.disconnect(_on_trigger_tower_event)

		_trigger_tower = new_trigger

		#connect new
		if is_instance_valid(_trigger_tower):
			_trigger_tower.on_event.connect(_on_trigger_tower_event)

func _on_back_updated(report: TowerTopologyService.Report) -> void:
	_last_back_report = report

	if not report.unique_towers.is_empty():
		_receiver_tower = report.unique_towers[0]
	else:
		_receiver_tower = null

#--- gameplay logic ---

#this is now only called when the front tower fires an event
func _on_trigger_tower_event(event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_DEALT:
		return

	#1. did the hit apply a status effect?
	var report = event.data as HitReportData
	if not report or report.statuses_applied.is_empty():
		return

	#check if any status had > 0 stacks applied
	var applied_status: bool = false
	for payload in report.statuses_applied.values():
		if payload.x > 0: #payload.x is stacks
			applied_status = true
			break

	if not applied_status:
		return

	#2. advance the receiver tower's cooldown
	_advance_receiver_cooldown()

func _advance_receiver_cooldown() -> void:
	if not is_instance_valid(_receiver_tower) or not is_instance_valid(_receiver_tower.attack_component):
		return

	var comp = _receiver_tower.attack_component
	if not comp.attack_data:
		return

	#calculate max cooldown using current modifiers
	var max_cd = comp.cooldown

	#calculate how much time to shave off
	var time_to_advance = max_cd * cooldown_advance_percent

	#advance the timer (prevent it from going below 0)
	comp.current_cooldown = maxf(0.0, comp.current_cooldown - time_to_advance)

	#visual feedback
	UI.floating_text_manager.show_icon(icon, _receiver_tower.global_position)
	#VFXManager.play_vfx(ID.Particles.BUFF_SPARKS, _receiver_tower.global_position, Vector2.UP)
	if is_instance_valid(animation_player):
		_play_animation(&"cast")

func _exit_tree() -> void:
	_unsubscribe()

	#clean up direct signal connection
	if is_instance_valid(_trigger_tower):
		if _trigger_tower.on_event.is_connected(_on_trigger_tower_event):
			_trigger_tower.on_event.disconnect(_on_trigger_tower_event)

#--- visualizer ---

func draw_visuals(canvas: RangeIndicator) -> void:
	var topo = Run.references.island.topology_service if is_instance_valid(Run.references.island) else null
	if not topo: return

	var margin: int = 2
	var cell_size := Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5

	var queries = [_make_query(true), _make_query(false)]

	for query in queries:
		#support preview mode by manually querying if no cached report exists
		var report = topo.query(unit as Tower, query)
		for cell: Vector2i in report.cells.values():
			var rect: Rect2 = Rect2(Island.cell_to_position(cell) - half_size, Vector2(cell_size, cell_size))
			canvas.draw_rect(rect, canvas.highlight_color, false, 1.0)
