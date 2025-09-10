extends Node2D
class_name Unit

signal on_event(event: GameEvent) #polymorphic event bus
signal components_ready()
signal died()
#core behaviours
@export var incorporeal: bool
@export var hostile: bool
@export var attack_only_when_blocked: bool

@export_category("Presentation")
@export var stat_displays : Array[StatDisplayInfo] = []

@export_category("Components")
@export var behavior: Behavior
@export var graphics: Sprite2D
@export var animation_player: AnimationPlayer
@export var modifiers_component: ModifiersComponent #used by most things
@export var health_component: HealthComponent
@export var movement_component: MovementComponent
@export var navigation_component: NavigationComponent

@export var range_component: RangeComponent
@export var attack_component: AttackComponent

@export var intrinsic_effects: Array[EffectPrototype] #effect prototypes that come with the unit type

var flux_value: float #how much flux this unit drops when killed / sold
#effect-related state
var effect_prototypes: Array[EffectPrototype] #for prototypes created during runtime
var effects: Dictionary[EffectPrototype.Schedule, Array] = {
	EffectPrototype.Schedule.MULTIPLICATIVE: [],
	EffectPrototype.Schedule.ADDITIVE: [],
	EffectPrototype.Schedule.REACTIVE: [],
} #sorted by Schedule, see EffectPrototype. each array contains EffectInstances
var effects_by_type: Dictionary[Effects.Type, Array] = {
	#each array contains EffectInstances
} # for lookup by type
#unit state
var unit_id: int = References.assign_unit_id()
var blocked: bool #whether this unit is currently blocked by a tower

var abstractive: bool: #this unit is not an actual unit (see prototypes, Towers)
	set(na):
		abstractive = na
		disabled = true
var disabled: bool

func _ready():
	name = name + " " + str(unit_id)
	_setup_event_bus()
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()
	
	if not is_instance_valid(behavior):
		behavior = DefaultBehavior.new()
		add_child(behavior)
	
	components_ready.emit()
	behavior.initialise(self)

func _process(delta: float):
	if not disabled and is_instance_valid(behavior):
		behavior.update(Clock.game_delta)

func _create_components() -> void:
	if modifiers_component == null:
		var n_modifiers_component: = ModifiersComponent.new()
		add_child(n_modifiers_component)
		modifiers_component = n_modifiers_component
	if movement_component == null: #by default, add an immobile movement component
		var n_movement_component: = MovementComponent.new()
		n_movement_component.movement_data = preload("res://Content/Movement/immobile_mvmt.tres")
		add_child(n_movement_component)
		movement_component = n_movement_component
	
func _prepare_components() -> void:
	unit_id = References.assign_unit_id() #assign this unit a unit id
	
	died.connect(func():
		if not self is Tower: #towers have their own flux value system 
			Player.flux += flux_value #reward player with flux
		Targeting.clear_damage(self) #clear any damage that might be locked on to us
		
		for effect_prototype: EffectPrototype in effect_prototypes:
			remove_effect(effect_prototype) #detach effects
	
		queue_free()
	)

	if navigation_component != null:
		navigation_component.inject_components(movement_component)
		navigation_component.blocked_by_tower.connect(func(tower):
			if is_instance_valid(tower) and tower is Tower:
				#command range component to prioritise the tower
				if is_instance_valid(range_component):
					range_component.priority_target_override = tower
				# command the movement component to stop moving
				if is_instance_valid(movement_component):
					movement_component.target_direction = Vector2.ZERO
				blocked = true
			else:
				blocked = false
		)
	
	if movement_component != null:
		movement_component.inject_components(graphics, modifiers_component)
		position = movement_component.position
	
	if health_component != null:
		health_component.inject_components(modifiers_component)
		health_component.died.connect(func():
			died.emit()
		)
	
	if attack_component != null:
		attack_component.attack_data
		attack_component.inject_components(modifiers_component)
	
	if range_component != null and attack_component.attack_data:
		range_component.inject_components(attack_component, modifiers_component)
	
	for child in get_children(true):
		if "unit" in child:
			child.unit = self

func _attach_intrinsic_effects() -> void:
	Waves.wave_started.connect(func(wave: int):
		var wave_data := WaveData.new()
		wave_data.wave = wave
		
		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.WAVE_STARTED
		evt.data = wave_data
		
		on_event.emit(evt)
	)
	
	#Player.before_compute_tower_capacity.connect(func():
		##allows towers to affect tower capacity
		#var evt := GameEvent.new()
		#evt.event_type = GameEvent.EventType.PRE_TOWER_CAPACITY_COMPUTE
		#evt.data = EventData.new()
		#
		#on_event.emit(evt)
	#)
	
	for effect_prototype: EffectPrototype in intrinsic_effects:
		apply_effect(effect_prototype)

func _setup_event_bus() -> void:
	on_event.connect(func(event: GameEvent):
		if disabled:
			return
		for schedule_class: EffectPrototype.Schedule in effects: #call effects by schedule class
			var scheduled_effects: Array = effects[schedule_class] #multiplicative -> additive -> reactive
			for effect_instance: EffectInstance in scheduled_effects:
				effect_instance.handle_event_unfiltered(event)
	)

func apply_effect(effect_prototype: EffectPrototype) -> void:
	effect_prototypes.append(effect_prototype)
	
	var effect_instance: EffectInstance = effect_prototype.create_instance()
	effects[effect_prototype.schedule].append(effect_instance)
	effect_instance.attach_to(self)
	
	var type = effect_prototype.effect_type
	if not effects_by_type.has(type):
		effects_by_type[type] = [] # Create an array for this type if it's the first one.

	effects_by_type[type].append(effect_instance)

func remove_effect(effect_prototype: EffectPrototype) -> void:
	var effects_to_remove: Array[EffectInstance] = []
	
	for effect_instance: EffectInstance in effects[effect_prototype.schedule]: #remove all child EffectInstances
		if effect_instance.effect_prototype == effect_prototype:
			effects_to_remove.append(effect_instance)
			
	for effect in effects_to_remove:
		effect.detach() #trigger effect's detach handler
		effects[effect_prototype.schedule].erase(effect)
		
		var type : Effects.Type = effect.effect_type
		if effects_by_type.has(type):
			effects_by_type[type].erase(effect)
			# If this was the last effect of its type, clean up the key.
			if effects_by_type[type].is_empty():
				effects_by_type.erase(type)
		
		effect.free()

	effect_prototypes.erase(effect_prototype)

func get_intrinsic_effect_attribute(effect_type: Effects.Type, attribute_name: StringName) -> Variant:
	print(effects_by_type)
	if not effects_by_type.has(effect_type):
		return null
		
	var instances = effects_by_type[effect_type]
	if instances.is_empty():
		return null
		
	#For intrinsic effects, we usually only care about the first one.
	var first_instance: EffectInstance = instances[0]
	# Using .get() is safer than `[]` as it returns null instead of crashing if the key doesn't exist.
	if first_instance.params.has(attribute_name): #first check params
		return first_instance.params.get(attribute_name, null)
	else: #fallback to checking state
		return first_instance.state.get(attribute_name, null)

func get_behavior_attribute(attribute_name: StringName) -> Variant:
	if not is_instance_valid(behavior):
		return null
	
	# check that the behavior actually implements the function before calling it.
	if behavior.has_method("get_display_data"):
		var data: Dictionary = behavior.get_display_data()
		# use .get() for a safe lookup that returns null if the key doesn't exist.
		return data.get(attribute_name, null)
		
	return null
	
func get_unit_state() -> void:
	if is_instance_valid(health_component):
		UI.update_unit_health.emit(self, health_component.max_health, health_component.health)

func set_initial_behaviour_state(behavior_packet: Dictionary): #used for environmental features with custom states (see terrain_expansion.gd)
	if not is_instance_valid(behavior):
		components_ready.connect(set_initial_behaviour_state.bind(behavior_packet), CONNECT_ONE_SHOT)
		return
	
	for attribute: StringName in behavior_packet:
		if attribute in behavior:
			behavior[attribute] = behavior_packet[attribute]
			print(attribute, " set! value:", behavior[attribute])
		else:
			push_warning(self, ": tried to apply behaviour modification of key: ", attribute, " but could not find matching behaviour attribute.")

func take_hit(hit: HitData):
	if not is_instance_valid(self):
		return
	
	if not is_instance_valid(health_component): #this specifically catches the player core, which doesnt have a health
		return
		
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.HIT_RECEIVED
	evt.data = hit

	on_event.emit(evt) #trigger any post-hit-received effects, accordingly mutate evt.data
	
	var benchmark: float = health_component.health
	health_component.health -= evt.data.damage
	var delta_health: float = benchmark - health_component.health #measure damage caused
	#compose a hit report, and send it to the source of the hit
	var hit_report := HitReportData.new()
	hit_report.damage_caused = delta_health
	if benchmark >= 0.01 and health_component.health < 0.01:
		hit_report.death_caused = true
		
	for modifier: Modifier in hit.modifiers:
		modifiers_component.add_modifier(modifier)

	for status: Attributes.Status in hit.status_effects:
		var stack: float = hit.status_effects[status].x
		var cooldown: float = hit.status_effects[status].y
		modifiers_component.add_status(status, stack, cooldown, hit.source.unit_id)
	
	var hit_report_evt := GameEvent.new()
	hit_report_evt.event_type = GameEvent.EventType.HIT_DEALT
	hit_report_evt.data = hit_report
	
	if not is_instance_valid(hit.source):
		return
	hit.source.on_event.emit(hit_report_evt) #cause source of hit to emit report

func deal_hit(hit: HitData, delivery_data : DeliveryData = null):
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.PRE_HIT_DEALT
	evt.data = hit
	
	on_event.emit(evt) #trigger any pre-hit-received effects, such as damage buffs
	#------ HANDOVER --------
	hit.recursion += 1 #increase recursion layer by 1
	if delivery_data == null: #fallback on guaranteed instant hit
		push_warning("no targeting data!")
		hit.target.take_hit(hit) #cause target to take hit
	else:
		CombatManager.resolve_hit(hit, delivery_data)

func get_terrain_base() -> Terrain.Base: #retrieves terrain base at current position
	return References.island.get_terrain_base(movement_component.cell_position)
	
func get_stat(attr: Attributes.id): #GENERIC get stat function, should only be used for ui related purposes
	if health_component != null:
		if attr == Attributes.id.MAX_HEALTH or attr == Attributes.id.REGENERATION or attr == Attributes.id.REGEN_PERCENT:
			return health_component.get_stat(modifiers_component, health_component.health_data, attr)

	if movement_component != null:
		if attr == Attributes.id.MAX_SPEED or attr == Attributes.id.ACCELERATION:
			return movement_component.get_stat(modifiers_component, movement_component.movement_data, attr)
	
	if attack_component != null:
		if attr == Attributes.id.DAMAGE or attr == Attributes.id.RADIUS or attr == Attributes.id.RANGE or attr == Attributes.id.COOLDOWN:
			return attack_component.get_stat(modifiers_component, attack_component.attack_data, attr)
