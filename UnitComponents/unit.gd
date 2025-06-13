extends Node2D
class_name Unit

@export var hostile: bool
@export_category("Components")
@export var graphics: Sprite2D
@export var modifiers_component: ModifiersComponent #used by most things
@export var health_component: HealthComponent
@export var movement_component: MovementComponent
@export var navigation_component: NavigationComponent

@export var range_component: RangeComponent
@export var attack_component: AttackComponent

@export var intrinsic_effects: Array[EffectPrototype] #effect prototypes that come with the unit type
var effect_prototypes: Array[EffectPrototype] #for prototypes created during runtime
var effects: Array[EffectInstance]

signal on_event(event: GameEvent) #polymorphic event bus
signal died()

var unit_id: int

var flux_value: float #how much flux this unit drops when killed

#runtime
var _cooldown: float

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
		Player.flux += flux_value
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
	
	if attack_component != null:
		attack_component.inject_components(modifiers_component)
	
	if range_component != null:
		range_component.inject_components(attack_component, modifiers_component)
	
	for child in get_children(true):
		if "unit" in child:
			child.unit = self

func _attach_intrinsic_effects() -> void:
	for effect_prototype: EffectPrototype in intrinsic_effects:
		apply_effect(effect_prototype)
		
	Waves.wave_started.connect(func(wave: int):
		var wave_data := WaveData.new()
		wave_data.wave = wave
		
		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.WAVE_STARTED
		evt.data = wave_data
		
		on_event.emit(evt)
	)

func apply_effect(effect_prototype: EffectPrototype) -> void:
	effect_prototypes.append(effect_prototype)
	
	var effect_instance: EffectInstance = effect_prototype.create_instance()
	effect_instance.attach_to(self)
	effects.append(effect_instance)

func remove_effect(effect_prototype: EffectPrototype) -> void:
	var effects_to_remove: Array[EffectInstance] = []
	
	for effect_instance: EffectInstance in effects: #remove all child EffectInstances
		if effect_instance.effect_prototype == effect_prototype:
			effects_to_remove.append(effect_instance)
			
	for effect in effects_to_remove:
		effect.detach() #trigger effect's detach handler
		effects.erase(effect)
		effect.free()
	
	effect_prototypes.erase(effect_prototype)

func _ready():
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()

func _process(delta: float):
	_cooldown += delta
	if attack_component == null or range_component == null:
		return
		
	if _cooldown >= attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN):
		var target = range_component.get_target() as Unit
		
		if hostile:
			pass

		if target:
			attack_component.attack(target)
			_cooldown = 0.0
			queue_redraw()
	
func take_hit(hit: HitData):
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.HIT_RECEIVED
	evt.data = hit
	
	Targeting.add_damage(hit.target, -hit.expected_damage) #remove the expected damage now that its been dealt
	on_event.emit(evt) #trigger any post-hit-received effects, accordingly mutate evt.data
	
	var benchmark: float = health_component.health
	health_component.health -= evt.data.damage
	var delta_health: float = benchmark - health_component.health #measured damage caused
	#compose a hit report, and send it to the source of the hit
	var hit_report := HitReportData.new()
	hit_report.damage_caused = delta_health
	if benchmark >= 0.01 and health_component.health < 0.01:
		hit_report.death_caused = true
		
	for modifier: Modifier in hit.modifiers:
		modifiers_component.add_modifier(modifier)
	
	var hit_report_evt := GameEvent.new()
	hit_report_evt.event_type = GameEvent.EventType.HIT_DEALT
	hit_report_evt.data = hit_report
	
	hit.source.on_event.emit(hit_report_evt) #cause source of hit to emit report

func deal_hit(hit: HitData):
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.PRE_HIT_DEALT
	evt.data = hit
	
	Targeting.add_damage(hit.target, hit.expected_damage) #adds expected damage to target in targeting coordinator
	on_event.emit(evt) #trigger any pre-hit-received effects, such as damage buffs
	
	#TODO: implement projectile traversal
	
	hit.recursion += 1 #increase recursion layer by 1
	hit.target.take_hit(hit) #cause target to take hit

func get_terrain_base() -> Terrain.Base: #retrieves terrain base at current position
	return References.island.get_terrain_base(movement_component.cell_position)
	
func get_stat(attr: Attributes.id): #GENERIC get stat function, should only be used for ui related purposes
	if health_component != null:
		if attr == Attributes.id.MAX_HEALTH:
			return health_component.get_stat(modifiers_component, health_component.health_data, attr)

	if movement_component != null:
		if attr == Attributes.id.MAX_SPEED:
			return movement_component.get_stat(modifiers_component, movement_component.movement_data, attr)
	
	if attack_component != null:
		if attr == Attributes.id.DAMAGE or attr == Attributes.id.RADIUS or attr == Attributes.id.RANGE or attr == Attributes.id.COOLDOWN:
			return attack_component.get_stat(modifiers_component, attack_component.attack_data, attr)
			
var draw_start: Vector2 = position
var draw_end: Vector2 = Vector2.ZERO
var draw_color: Color = Color.BLACK

func _draw():
	draw_line(draw_start - position, draw_end - position, draw_color, 2.0)
