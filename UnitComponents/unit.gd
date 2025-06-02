extends Node2D
class_name Unit

@export var hostile: bool
@export_category("Components")
@export var graphics: Sprite2D
@export var effects_component: EffectsComponent #used by most things
@export var health_component: HealthComponent
@export var movement_component: MovementComponent
@export var navigation_component: NavigationComponent

signal on_event(event: GameEvent) #polymorphic event bus

var unit_id: int

func _create_components():
	if effects_component == null:
		var n_effects_component: = EffectsComponent.new()
		add_child(n_effects_component)
	if movement_component == null: #by default, add an immobile movement component
		var n_movement_component: = MovementComponent.new()
		n_movement_component.movement_data = preload("res://Data/Movement/immobile_mvmt.tres")
		add_child(n_movement_component)

func _prepare_components():
	unit_id = References.assign_unit_id()
	
	
	if navigation_component != null:
		navigation_component.inject_components(movement_component)
	
	if movement_component != null:
		movement_component.inject_components(graphics, effects_component)
		position = movement_component.position
	
	if health_component != null:
		health_component.inject_components(effects_component)
		health_component.died.connect(func():
			queue_free()
		)
	
	for child in get_children(true):
		if child is Hitbox:
			child.unit = self

func _ready():
	_create_components()
	_prepare_components()
	
func take_hit(amount: float):
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.HIT_RECEIVED
	evt.target = self
	evt.data = {
		"damage" : amount,
	}
	
	on_event.emit(evt) #trigger any post-hit-received effects, accordingly mutate evt.data
	
	health_component.health -= evt.damage
	

func deal_hit(hamount: float):
	pass
