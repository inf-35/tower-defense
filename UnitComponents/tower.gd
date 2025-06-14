extends Unit
class_name Tower

signal adjacency_updated(new_adjacencies: Dictionary[Vector2i, Tower]) #Island hooks onto this

@export var type: Towers.Type
var facing: Facing: #which direction the tower is facing
	set(new_facing):
		facing = new_facing
		if graphics:
			graphics.rotation = facing * PI * 0.5

enum Facing {
	UP,
	LEFT,
	DOWN,
	RIGHT,
}

var tower_position: Vector2i = Vector2i.ZERO:
	set(new_pos):
		tower_position = new_pos
		movement_component.position = Island.cell_to_position(tower_position)
		
func _ready():
	_setup_event_bus()
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()
	
	adjacency_updated.connect(func(new_adjacencies: Dictionary[Vector2i, Tower]): #receive data from Island
		var adjacency_data := AdjacencyReportData.new() #broadcast into effects system
		adjacency_data.adjacent_towers = new_adjacencies
		adjacency_data.pivot = self
		
		var event := GameEvent.new()
		event.event_type = GameEvent.EventType.ADJACENCY_UPDATED
		event.data = adjacency_data
		
		on_event.emit(event)
	)
