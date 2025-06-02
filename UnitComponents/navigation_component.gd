extends UnitComponent
class_name NavigationComponent

var movement_component: MovementComponent

func inject_components(movement: MovementComponent):
	movement_component = movement


var goal: Vector2i = Vector2i.ZERO
var _current_waypoint_index: int:
	set(ncwi):
		_current_waypoint_index = ncwi
		if len(_path) > (_current_waypoint_index):
			_current_waypoint = _path[_current_waypoint_index]
			movement_component.target_position = Island.cell_to_position(_current_waypoint)
		else:
			movement_component.target_direction = Vector2(0,0)

var _current_waypoint: Vector2i

var _path: Array[Vector2i] = []:
	set(new_path):
		_path = new_path
		_current_waypoint_index = 0

func _ready():
	Navigation.field_cleared.connect(func():
		update_path()
	)
	
	_stagger += randi_range(0, _STAGGER_CYCLE)
	_STAGGER_CYCLE = 5
	
func update_path():
	var path_data: Navigation.PathData = Navigation.find_path(movement_component.cell_position)
	if path_data.status == Navigation.PathData.Status.building_path:
		Navigation.request_path_promise(Navigation.PathPromise.new(
			self,
			movement_component.cell_position,
			goal
		))
		unit.graphics.modulate = Color(0.0, 1.0, 1.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)
	else:
		_path = path_data.path
		unit.graphics.modulate = Color(1.0, 0.0, 1.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)

func receive_path_data(path_data: Navigation.PathData): #used by Navigation to fulfill promises
	if path_data.status == Navigation.PathData.Status.building_path: #keep requesting path until we get back a good reply
		push_warning(self, " navigation promise bounced!")
		Navigation.request_path_promise(Navigation.PathPromise.new(
			self,
			movement_component.cell_position,
			goal
		))
	else:
		_path = path_data.path
		unit.graphics.modulate = Color(1.0, 0.0, 0.0)
		get_tree().create_timer(0.2).timeout.connect(func():
			unit.graphics.modulate = Color(1.0, 1.0, 1.0)
		)
		
	
func _process(delta: float):
	_stagger += 1
	if _stagger % _STAGGER_CYCLE != 1:
		return
		
	if movement_component == null:
		return
	
	if _path.is_empty(): #path empty? get path
		update_path()
		movement_component.target_position = Island.cell_to_position(_current_waypoint)
	
	if _path.is_empty(): #path still empty? path unavailable
		movement_component.target_direction = Vector2.ZERO
		return
	
	if movement_component.cell_position == goal:
		movement_component.target_position = Island.cell_to_position(goal)
		return
	
	if (movement_component.position - Island.cell_to_position(_current_waypoint)).length_squared() < 50:
		_current_waypoint_index += 1
