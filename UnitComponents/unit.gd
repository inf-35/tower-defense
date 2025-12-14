extends Node2D
class_name Unit
@warning_ignore_start("unused_signal")

signal on_event(event: GameEvent) #polymorphic event bus
signal components_ready()
signal died(hit_report_data: HitReportData) ##fires upon unit death. hooks onto on_killed, which defines unit death behaviour. hit_report_data contains info of the hit that killed the enemy, if any

signal changed_cell(old_cell: Vector2i, new_cell: Vector2i) ##fires upon unit moving from one cell to another
#core behaviours
@export var incorporeal: bool ##this unit basically doesnt exist (think tower previews)
@export var phasing: bool ##this unit can phase through walls NOTE: change navigation component's ignore_walls to modify pathfinding behaviour
@export var hostile: bool ##is this unit hostile to the player?
@export var attack_only_when_blocked: bool ##does this unit attack only if blocked by a tower?

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
var disabled: bool:
	set(nd):
		disabled = nd
		if graphics and graphics.material != null:
			graphics.material.set_shader_parameter(&"overlay_color", Color(0.0, 0.0, 0.0, 1.0) if disabled else Color(0,0,0,0))
			graphics.material.set_shader_parameter(&"transparency", 0.3 if disabled else 1.0)

const _DEBUG_DRAW: bool = false

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

func _process(_delta: float):
	if not disabled and is_instance_valid(behavior):
		behavior.update(Clock.game_delta)

	if _DEBUG_DRAW:
		queue_redraw()

func _create_components() -> void:
	if modifiers_component == null:
		var n_modifiers_component: = ModifiersComponent.new()
		add_child(n_modifiers_component)
		modifiers_component = n_modifiers_component
	if movement_component == null: #by default, add an immobile movement component
		var n_movement_component: = MovementComponent.new()
		n_movement_component.movement_data = load("res://Content/Movement/immobile_mvmt.tres")
		add_child(n_movement_component)
		movement_component = n_movement_component
	
func _prepare_components() -> void:
	unit_id = References.assign_unit_id() #assign this unit a unit id
	died.connect(func(hit_report_data: HitReportData):
		#NOTE: the global unit_died signal must fire before execution of on_killed, since on_killed
		#could destroy the instance, and we want the instance intact for any post-kill abilities
		References.unit_died.emit(self, hit_report_data) #link local and global died signals
		on_killed(hit_report_data) #connect the died signal to the on_killed method. for units this frees the instance
		#(which implements flux reward and ruins behaviour for units and towers respectively)
	)
	changed_cell.connect(func(new_cell: Vector2i, old_cell: Vector2i):
		References.unit_changed_cell.emit(self, new_cell, old_cell)
	)
	
	if graphics != null:
		var unit_effects_shader_material: ShaderMaterial = ShaderMaterial.new()
		unit_effects_shader_material.shader = preload("res://Shaders/unit_effects.gdshader")
		graphics.material = unit_effects_shader_material

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
				if is_instance_valid(range_component):
					range_component.priority_target_override = null
				blocked = false
		)
	
	if movement_component != null:
		movement_component.inject_components(graphics, modifiers_component)
		position = movement_component.position
		
		movement_component.movement_to_cell.connect(changed_cell.emit)
	
	if health_component != null:
		health_component.inject_components(modifiers_component)
	
	if attack_component != null:
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
		
		if event.data.recursion > EffectInstance.GLOBAL_RECURSION_LIMIT:
			return #prevent recursion
			
		for schedule_class: EffectPrototype.Schedule in effects: #call effects by schedule class
			var scheduled_effects: Array = effects[schedule_class] #multiplicative -> additive -> reactive
			for effect_instance: EffectInstance in scheduled_effects:
				effect_instance.handle_event_unfiltered(event)
				
		Player.on_event.emit(self, event) #link local and global event bus (local events firing earlier)
		#TODO: implement scheduling
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
	if behavior.has_method(&"get_display_data"):
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
		return #wait until everything's ready
	
	for attribute: StringName in behavior_packet:
		if attribute in behavior:
			behavior[attribute] = behavior_packet[attribute]
		else:
			push_error(self, ": tried to apply behaviour modification of key: ", attribute, " but could not find matching behaviour attribute.")
	UI.update_unit_state.emit(self)

func take_hit(hit: HitData):
	if not is_instance_valid(self):
		return
	
	if not is_instance_valid(health_component): #this specifically catches the player core, which doesnt have a health
		return
		
	var source_position: Vector2 = hit.source.global_position if is_instance_valid(hit.source) else self.global_position #used to render ccosmetic particle effects
		
	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.HIT_RECEIVED
	evt.data = hit as HitData
	on_event.emit(evt) #trigger any local post-hit-received effects, accordingly mutate evt.data
	References.unit_took_hit.emit(self, evt.data as HitData) #trigger any global post-hit-received effects, according mutate evt.data
	
	var damage: float = evt.data.damage
	var benchmark: float = health_component.health #NOTE: this indirect system of measurement is used due to custom setter functionality
	health_component.take_damage(damage, evt.data.breaking)
	#measure what happened
	var delta_health: float = benchmark - health_component.health #measure damage caused
	var unit_dead: bool = is_zero_approx(health_component.health)
	#compose a hit report, and send it to the source of the hit
	var hit_report := HitReportData.new()
	hit_report.recursion = hit.recursion #NOTE: a hit and its corresponding report are of the SAME recursion
	hit_report.target = self
	hit_report.source = hit.source
	hit_report.damage_caused = delta_health
	
	if unit_dead: #TODO: separation of logic (decouple shader)
		hit_report.death_caused = true
		
		hit_report.flux_value = flux_value #submit base flux value to be modified
		
		ParticleManager.play_particles(ID.Particles.ENEMY_DEATH_SPARKS, self.global_position, (self.global_position - source_position).angle())
		
		died.emit(hit_report) #NOTE: this is when the unit dies
	else:
		ParticleManager.play_particles(ID.Particles.ENEMY_HIT_SPARKS, self.global_position, (self.global_position - source_position).angle())
		
		var shader_material: ShaderMaterial = graphics.material as ShaderMaterial
		shader_material.set_shader_parameter(&"flash_intensity", 1.0)
		
		var flash_tween := create_tween()
		flash_tween.tween_property(shader_material, "shader_parameter/flash_intensity", 0.0, 0.25)
		flash_tween.play()
		
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
	if delivery_data == null: #fallback on guaranteed instant hit
		push_warning("no targeting data!")
		hit.target.take_hit(hit) #cause target to take hit
	else:
		CombatManager.resolve_hit(hit, delivery_data)
		
# this is a new virtual function that deals with actual death (connects to the died signal)
# towers will override this with their ruin logic.
func on_killed(hit_report_data: HitReportData) -> void:
	if not self is Tower: #towers have their own flux value system 
		Player.flux += hit_report_data.flux_value #reward player with flux
	Targeting.clear_damage(self) #clear any damage that might be locked on to us
	
	for effect_prototype: EffectPrototype in effect_prototypes:
		remove_effect(effect_prototype) #detach effects

	queue_free()

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

func _draw() -> void:
	# 1. VISUALIZE PATH (Blue Line)
	if not _DEBUG_DRAW:
		return

	if is_instance_valid(navigation_component) and not navigation_component._path.is_empty():
		if navigation_component._current_waypoint_index < navigation_component._path.size():
			var next_tile = navigation_component._path[navigation_component._current_waypoint_index]
			var next_pos = Island.cell_to_position(next_tile)
			draw_line(Vector2.ZERO, to_local(next_pos), Color.BLUE, 2.0)

	# 2. VISUALIZE TARGET (Red/Yellow Line)
	if is_instance_valid(range_component):
		var target = range_component.get_target()
		if is_instance_valid(target):
			var local_target = to_local(target.global_position)

			# YELLOW = Priority Override (Blocking Tower)
			# RED = Normal Target (Closest/Health/etc)
			var color = Color.RED
			if range_component.priority_target_override == target:
				color = Color.YELLOW

			draw_line(Vector2.ZERO, local_target, color, 3.0)
			draw_circle(local_target, 5.0, color)
