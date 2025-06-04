extends Unit
class_name Tower

@export var type: Towers.Type
@export var tower_data: TowerData

@export var range_component: RangeComponent
@export var attack_component: AttackComponent

var tower_position: Vector2i = Vector2i.ZERO:
	set(new_pos):
		tower_position = new_pos
		movement_component.position = Island.cell_to_position(tower_position)
	
var _cooldown: float = 0.0

func _ready():
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()

	
	attack_component.attack_data = tower_data.attack
	attack_component.inject_components(modifiers_component)

func _process(delta: float):
	if tower_data == null or range_component == null or attack_component == null:
		return
	if movement_component == null:
		return

	_cooldown += delta

	if _cooldown >= tower_data.attack.cooldown:
		var target = range_component.get_target() as Unit
		
		if target:
			attack_component.attack(target)
			_cooldown = 0.0
	queue_redraw()
			
var draw_start: Vector2 = position
var draw_end: Vector2 = Vector2.ZERO
var draw_color: Color = Color.BLACK

func _draw():
	draw_line(draw_start - position, draw_end - position, draw_color, 2.0)
