extends Unit
class_name Tower

signal adjacency_updated(new_adjacencies: Dictionary[Vector2i, Tower]) #Island hooks onto this

@export var type: Towers.Type
var level: int = 0:
	set(new_level):
		level = new_level
		UI.update_unit_state.emit(self)

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

func _create_hitbox():
	var hitbox := Hitbox.new()
	var collision_shape := CollisionShape2D.new()
	var shape_bound := RectangleShape2D.new()
	shape_bound.size = Vector2(Island.CELL_SIZE, Island.CELL_SIZE)
	
	collision_shape.shape = shape_bound
	hitbox.collision_mask = 0
	hitbox.collision_layer = Hitbox.get_mask(hostile)
	hitbox.unit = self
	
	hitbox.add_child(collision_shape)
	add_child(hitbox)
		
func _ready():
	_setup_event_bus()
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()
	_create_hitbox()
	
	level = 1
		
	adjacency_updated.connect(func(new_adjacencies: Dictionary[Vector2i, Tower]): #receive data from Island
		var adjacency_data := AdjacencyReportData.new() #broadcast into effects system
		adjacency_data.adjacent_towers = new_adjacencies
		adjacency_data.pivot = self
		
		var event := GameEvent.new()
		event.event_type = GameEvent.EventType.ADJACENCY_UPDATED
		event.data = adjacency_data
		
		on_event.emit(event)
	)
