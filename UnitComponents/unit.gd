extends Node2D
class_name Unit

@export var hostile: bool
@export_category("Components")
@export var graphics: Sprite2D
@export var modifiers_component: ModifiersComponent #used by most things
@export var health_component: HealthComponent
@export var movement_component: MovementComponent
@export var navigation_component: NavigationComponent

@export var intrinsic_effects: Array[EffectPrototype] #effect prototypes that come with the unit type
var effects: Array[EffectInstance]

signal on_event(event: GameEvent) #polymorphic event bus
signal died()

var unit_id: int
var part_of_wave: bool = false

func _create_components():
	if modifiers_component == null:
		var n_modifiers_component: = ModifiersComponent.new()
		add_child(n_modifiers_component)
	if movement_component == null: #by default, add an immobile movement component
		var n_movement_component: = MovementComponent.new()
		n_movement_component.movement_data = preload("res://Data/Movement/immobile_mvmt.tres")
		add_child(n_movement_component)

func _prepare_components():
	unit_id = References.assign_unit_id()
	
	died.connect(func():
		if part_of_wave:
			Waves.alive_enemies -= 1
		queue_free()
	)

	if navigation_component != null:
		navigation_component.inject_components(movement_component)
	
	if movement_component != null:
		movement_component.inject_components(graphics, modifiers_component)
		position = movement_component.position
	
	if health_component != null:
		health_component.inject_components(modifiers_component)
		health_component.died.connect(func():
			died.emit()
		)
	
	for child in get_children(true):
		if "unit" in child:
			child.unit = self

func _attach_intrinsic_effects() -> void:
	for effect_prototype: EffectPrototype in intrinsic_effects:
		var effect_instance: EffectInstance = effect_prototype.create_instance()
		effect_instance.attach_to(self)
		effects.append(effect_instance)
		
	Waves.wave_started.connect(func(wave: int):
		var wave_data := WaveData.new()
		wave_data.wave = wave
		
		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.WAVE_STARTED
		evt.data = wave_data
		
		on_event.emit(evt)
	)

func _ready():
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()
	
func take_hit(hit: HitData):
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.HIT_RECEIVED
	evt.data = hit
	
	on_event.emit(evt) #trigger any post-hit-received effects, accordingly mutate evt.data

	health_component.health -= evt.data.damage
	#compose a hit report, and send it to the source of the hit
	var hit_report := HitReportData.new()
	hit_report.damage_caused = evt.data.damage #TODO: change this to like actual readings
	
	var hit_report_evt := GameEvent.new()
	hit_report_evt.event_type = GameEvent.EventType.HIT_DEALT
	hit_report_evt.data = hit_report
	
	hit.source.on_event.emit(hit_report_evt) #cause source of hit to emit report
	

func deal_hit(hit: HitData):
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.PRE_HIT_DEALT
	evt.data = hit
	
	on_event.emit(evt) #trigger any pre-hit-received effects, such as damage buffs
	
	hit.recursion += 1 #increase recursion layer by 1
	hit.target.take_hit(hit) #cause target to take hit

func get_terrain_base() -> Terrain.Base: #retrieves terrain base at current position
	return References.island.get_terrain_base(movement_component.cell_position)
	
