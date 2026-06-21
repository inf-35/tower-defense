extends Node2D
class_name Unit
@warning_ignore_start("unused_signal")

signal on_event(event: GameEvent) #polymorphic event bus
signal components_ready() ##fires when all components and the unit is ready
signal died(hit_report_data: HitReportData) ##fires upon unit death. hooks onto on_killed, which defines unit death behaviour. hit_report_data contains info of the hit that killed the enemy, if any

signal changed_cell(old_cell: Vector2i, new_cell: Vector2i) ##fires upon unit moving from one cell to another

var HP_BAR_SCENE: PackedScene = load("res://UI/unit_hp_bar/unit_hp_bar.tscn")
#core behaviours
@export var incorporeal: bool ##this unit basically doesnt exist (think tower previews)
@export var phasing: bool ##this unit can phase through walls NOTE: change navigation component's ignore_walls to modify pathfinding behaviour
@export var hostile: bool ##is this unit hostile to the player?
@export var attack_only_when_blocked: bool ##does this unit attack only if blocked by a tower?
@export var _DEBUG_DRAW: bool = false

@export_category("Presentation")
@export var stat_displays: Array[StatDisplayInfo] = []

@export_category("Components")
@export var behavior: Behavior
@export var graphics: Sprite2D
@export var hitbox: Hitbox
@export var animation_player: AnimationPlayer
@export var modifiers_component: ModifiersComponent #used by most things
@export var health_component: HealthComponent
@export var movement_component: MovementComponent
@export var navigation_component: NavigationComponent

@export var range_component: RangeComponent
@export var attack_component: AttackComponent
@export var corpse_component: CorpseComponent
@export var buff_component: BuffComponent

@export var intrinsic_effects: Array[EffectPrototype] #effect prototypes that come with the unit type

var flux_value: float #how much flux this unit drops when killed / sold
var strength: float ##how "strong" this unit is, used for targeting
#effect-related state
var effect_prototypes: Array[EffectPrototype] #for prototypes created during runtime
var effects: Dictionary[EffectPrototype.Schedule, Dictionary] = { ##2d table, [x][y] -> Array[EffectInstance] where x is schedule and y is event hook.
	EffectPrototype.Schedule.MULTIPLICATIVE: {},
	EffectPrototype.Schedule.ADDITIVE: {},
	EffectPrototype.Schedule.REACTIVE: {},
}
#unit state
var unit_id: int = Run.references.assign_unit_id()
var enemy_type: Units.Type ##assigned by Units.create_unit
var blocked: bool #whether this unit is currently blocked by a tower

var abstractive: bool: #fathis unit is not an actual unit (see prototypes, Towers)
	set(na):
		abstractive = na
		if abstractive:
			disabled = true
var disabled: bool:
	set(nd):
		disabled = nd
		if disabled:
			set_tint_layer(TintService.LAYER_DISABLED, Color(0.0, 0.0, 0.0, 0.3), 1.0, true)
		else:
			clear_tint_layer(TintService.LAYER_DISABLED)

var is_ready: bool = false
var tint_service: TintService = TintService.new()
var _base_graphics_scale: Vector2 = Vector2.ONE
var _motion_graphics_scale: Vector2 = Vector2.ONE
var _action_graphics_scale: Vector2 = Vector2.ONE
var _action_graphics_tween: Tween

const BEHAVIOR_CYCLE: int = 3
var behavior_stagger: int = 0

func _ready() -> void:
	add_to_group(DebugAssistant.GROUP_UNITS)
	behavior_stagger = randi_range(0, BEHAVIOR_CYCLE)
	name = name + " " + str(unit_id)
	_setup_event_bus()
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()

	if not is_instance_valid(behavior):
		behavior = DefaultBehavior.new()
		add_child(behavior)

	is_ready = true
	components_ready.emit()
	behavior.initialise(self)

func _process(_delta: float) -> void:
	behavior_stagger += 1
	if not disabled and is_instance_valid(behavior) and behavior_stagger % BEHAVIOR_CYCLE == 0:
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

	if not is_instance_valid(hitbox):
		hitbox = Hitbox.new() #generate range area
		hitbox.name = "Hitbox"
		hitbox.unit = self
		add_child.call_deferred(hitbox)

		var shape := RectangleShape2D.new()
		shape.size = Vector2(Island.CELL_SIZE, Island.CELL_SIZE)

		var collision := CollisionShape2D.new()
		collision.shape = shape
		hitbox.add_child.call_deferred(collision)
		#set detection bitmasks
		hitbox.collision_layer = Hitbox.get_mask(hostile)
		hitbox.collision_mask = 0
		hitbox.monitoring = false
		hitbox.monitorable = true

	if corpse_component == null:
		for child in get_children():
			if child is CorpseComponent:
				corpse_component = child
				break

	if corpse_component == null and _needs_corpse_component():
		var n_corpse_component := CorpseComponent.new()
		n_corpse_component.name = "CorpseComponent"
		add_child(n_corpse_component)
		corpse_component = n_corpse_component

	if buff_component == null:
		for child in get_children():
			if child is BuffComponent:
				buff_component = child
				break

	if buff_component == null and _needs_buff_component():
		var n_buff_component := BuffComponent.new()
		n_buff_component.name = "BuffComponent"
		add_child(n_buff_component)
		buff_component = n_buff_component

func _needs_corpse_component() -> bool:
	return hostile and not abstractive and is_instance_valid(graphics)

func _needs_buff_component() -> bool:
	return self is Tower and Towers.is_tower_buff_source((self as Tower).type)

func _prepare_components() -> void:
	unit_id = Run.references.assign_unit_id() #assign this unit a unit id

	if is_instance_valid(hitbox) and abstractive:
		hitbox.monitorable = false #disables the hitbox (if abstractive)

	died.connect(func(hit_report_data: HitReportData):
		hit_report_data.flux_value = flux_value #submit base flux value to be modified

		on_killed(hit_report_data) #connect the died signal to the on_killed method. for units this frees the instance
		#(which implements flux reward and ruins behaviour for units and towers respectively)
		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.DIED
		evt.data = hit_report_data
		on_event.emit(evt) #this also fires the global died signal
	)
	changed_cell.connect(func(new_cell: Vector2i, old_cell: Vector2i):
		var changed_cell_data := ChangedCellData.new()
		changed_cell_data.new_cell = new_cell
		changed_cell_data.original_cell = old_cell

		var evt := GameEvent.new()
		evt.event_type = GameEvent.EventType.CHANGED_CELL
		evt.data = changed_cell_data
		on_event.emit(evt)
	)

	if graphics != null:
		graphics.visible = not DebugAssistant.hide_unit_graphics
		tint_service.initialise(self, graphics)
		set_tint_layer(
			TintService.LAYER_SIDE_TINT,
			_resolve_tint_target_from_multiplier(DebugAssistant.enemy_graphics_tint if hostile else DebugAssistant.allied_graphics_tint)
		)
		_base_graphics_scale = graphics.scale
		_apply_graphics_scale_layers()

	if navigation_component != null:
		navigation_component.inject_components(movement_component)
		navigation_component.blocked_by_tower.connect(func(tower):
			if is_instance_valid(tower) and tower is Tower:
				#command range component to prioritise the tower
				if is_instance_valid(range_component):
					range_component.priority_target_override = tower
				#command the movement component to stop moving
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
		_attach_health_bar()

	if attack_component != null:
		attack_component.inject_components(modifiers_component)

	if range_component != null and attack_component.attack_data:
		range_component.inject_components(attack_component, modifiers_component)

	for child in get_children(true):
		if "unit" in child:
			child.unit = self

func _setup_event_bus() -> void:
	Run.player.on_event.connect(func(_unit: Unit, event: GameEvent): #propagate wave events from global to local scope
		if not (event.event_type == GameEvent.EventType.WAVE_PREP_STARTED or event.event_type == GameEvent.EventType.WAVE_STARTED or event.event_type == GameEvent.EventType.WAVE_ENDED):
			return

		on_event.emit(event)
	)

	on_event.connect(func(event: GameEvent): #setup main event bus
		if event.data.recursion > EffectInstance.GLOBAL_RECURSION_LIMIT:
			return #prevent recursion

		event.unit = self
		#execute local effects
		for schedule_class: EffectPrototype.Schedule in effects: #call effects by schedule class
			var scheduled_effects: Dictionary = effects[schedule_class] #multiplicative -> additive -> reactive
			if not scheduled_effects.has(event.event_type):
				continue #no scheduled effects of correct event type
			for effect_instance: EffectInstance in scheduled_effects[event.event_type]:
				effect_instance.handle_event_unfiltered(event)
		#exectue global effects
		if event.event_type == GameEvent.EventType.WAVE_PREP_STARTED or event.event_type == GameEvent.EventType.WAVE_STARTED or event.event_type == GameEvent.EventType.WAVE_ENDED: #reject up-propagation of inherently global events
			return
		Run.player.on_event.emit(self, event) #link local and global event bus (local events firing earlier)
	)

func _attach_health_bar() -> void:
	if abstractive or disabled or DebugAssistant.disable_hp_bars:
		return

	if not HP_BAR_SCENE.can_instantiate():
		push_error("Unit: hp bar scene could not be instantiated.")
		return

	var hp_bar: UnitHPBar = HP_BAR_SCENE.instantiate()
	if not is_instance_valid(hp_bar):
		push_error("Unit: hp bar scene instantiated to an invalid control.")
		return

	add_child.call_deferred(hp_bar)
	hp_bar.ready.connect(func():
		if not hp_bar.has_method(&"setup"):
			push_error("Unit: hp bar scene is missing setup().")
			return
		hp_bar.call(&"setup", self, health_component)
		#connect hitbox mouse events to the hp bar
		var hitbox_node := hitbox
		hitbox_node.visible = true #doesnt actl affect graphics, just makes it hoverable
		hitbox_node.process_mode = Node.PROCESS_MODE_ALWAYS #allows hovering to work even when paused
		if is_instance_valid(hitbox_node):
			#ensure hitbox is pickable
			hitbox_node.input_pickable = true

			hitbox_node.mouse_entered.connect(Callable(hp_bar, &"on_mouse_entered"))
			hitbox_node.mouse_exited.connect(Callable(hp_bar, &"on_mouse_exited")),

		CONNECT_ONE_SHOT
	)

func _attach_intrinsic_effects() -> void:
	for effect_prototype: EffectPrototype in intrinsic_effects:
		apply_effect(effect_prototype)

func set_motion_graphics_scale(scale_multiplier: Vector2) -> void: ##updates the locomotion-owned visual scale layer without disturbing transient action pulses
	_motion_graphics_scale = scale_multiplier
	_apply_graphics_scale_layers()

func get_motion_graphics_scale() -> Vector2: ##returns the locomotion-owned graphics scale layer for systems that need to ease back toward neutral
	return _motion_graphics_scale

func play_action_squash_stretch(
	stretch_scale: Vector2 = Vector2(0.84, 1.18),
	rebound_scale: Vector2 = Vector2(1.05, 0.97),
	stretch_duration: float = 0.045,
	rebound_duration: float = 0.085
) -> void: ##plays a short squash-stretch pulse on the unit graphics while preserving authored base scale and other scale channels
	if not is_instance_valid(graphics):
		return

	if is_instance_valid(_action_graphics_tween):
		_action_graphics_tween.kill()

	_action_graphics_tween = create_tween()
	_action_graphics_tween.tween_method(_set_action_graphics_scale, _action_graphics_scale, stretch_scale, stretch_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_action_graphics_tween.tween_method(_set_action_graphics_scale, stretch_scale, rebound_scale, rebound_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_action_graphics_tween.tween_method(_set_action_graphics_scale, rebound_scale, Vector2.ONE, rebound_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_action_graphics_scale(scale_multiplier: Vector2) -> void: ##drives the transient action-owned visual scale layer during squash-stretch tweens
	_action_graphics_scale = scale_multiplier
	_apply_graphics_scale_layers()

func _apply_graphics_scale_layers() -> void: ##combines authored base scale with locomotion and action scale layers before writing to the graphics node
	if not is_instance_valid(graphics):
		return

	graphics.scale = Vector2(
		_base_graphics_scale.x * _motion_graphics_scale.x * _action_graphics_scale.x,
		_base_graphics_scale.y * _motion_graphics_scale.y * _action_graphics_scale.y
	)

func set_tint_layer(layer: int, color: Color, strength: float = 1.0, affect_alpha: bool = false, blend_mode: int = TintService.BlendMode.MODULATE) -> void: ##registers or updates one fixed tint layer under the shared unit tint interface
	tint_service.set_tint_layer(layer, color, strength, affect_alpha, blend_mode)

func clear_tint_layer(layer: int) -> void: ##removes one fixed tint layer and recomposes the remainder
	tint_service.clear_tint_layer(layer)

func tween_tint_layer(
	layer: int,
	from_color: Color,
	to_color: Color,
	duration: float,
	affect_alpha: bool = false,
	trans: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
	ignore_pause: bool = false,
	blend_mode: int = TintService.BlendMode.MODULATE
) -> void: ##tweens the target color of one fixed tint layer through the shared tint service
	tint_service.tween_tint_layer(layer, from_color, to_color, duration, affect_alpha, trans, ease, ignore_pause, blend_mode)

func tween_tint_strength(
	layer: int,
	from: float,
	to: float,
	duration: float,
	trans: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
	ignore_pause: bool = false
) -> void: ##tweens the strength of one fixed tint layer through the shared tint service
	tint_service.tween_tint_strength(layer, from, to, duration, trans, ease, ignore_pause)

func pulse_tint_layer(
	layer: int,
	color: Color,
	peak_strength: float,
	ramp_in_duration: float,
	ramp_out_duration: float,
	affect_alpha: bool = false,
	trans: Tween.TransitionType = Tween.TRANS_LINEAR,
	ease: Tween.EaseType = Tween.EASE_IN_OUT,
	ignore_pause: bool = false,
	blend_mode: int = TintService.BlendMode.MODULATE
) -> void: ##plays a shared tint pulse on one fixed layer without bypassing the unit tint stack
	tint_service.pulse_tint_layer(layer, color, peak_strength, ramp_in_duration, ramp_out_duration, affect_alpha, trans, ease, ignore_pause, blend_mode)

func play_hit_flash(duration: float = 0.25, ignore_pause: bool = false) -> void: ##plays the standard hit flash through the shared unit tint service
	tint_service.play_hit_flash(duration, ignore_pause)

func _resolve_tint_target_from_multiplier(multiplier: Color) -> Color: ##converts legacy multiplier-style tint authored data into a root-modulate tint target under the new mix-based pipeline
	if not is_instance_valid(graphics):
		return Color.WHITE

	var base_color: Color = graphics.modulate
	return Color(
		base_color.r * multiplier.r,
		base_color.g * multiplier.g,
		base_color.b * multiplier.b,
		base_color.a * multiplier.a
	)

func apply_effect(effect_prototype: EffectPrototype, stacks: int = 1) -> EffectInstance: ##negative for removing without clearing
	if stacks < 0:
		if not get_effect_instance_by_prototype(effect_prototype):
			return null

		var effect_instance := get_effect_instance_by_prototype(effect_prototype)
		effect_instance.stacks += stacks
		if effect_instance.stacks <= 0:
			remove_effect(effect_prototype)

		return null

	if get_effect_instance_by_prototype(effect_prototype):
		get_effect_instance_by_prototype(effect_prototype).stacks += stacks
		return get_effect_instance_by_prototype(effect_prototype)

	var effect_instance: EffectInstance = effect_prototype.create_instance()
	var schedule := effect_instance.schedule
	for event_hook: GameEvent.EventType in effect_instance.event_hooks:
		if not effects[schedule].has(event_hook):
			effects[schedule][event_hook] = []
		effects[schedule][event_hook].append(effect_instance)
	effect_instance.stacks = stacks
	effect_instance.attach_to(self)
	effect_prototypes.append(effect_prototype)
	return effect_instance

func remove_effect(effect_prototype: EffectPrototype) -> void: ##clears all effects, regardless of number
	var effects_to_remove: Array[EffectInstance] = get_effect_instances_by_prototype(effect_prototype)

	for effect in effects_to_remove:
		effect.detach() #trigger effect's detach handler
		for event_hook in effect.event_hooks:
			effects[effect.schedule][event_hook].erase(effect)

		effect.free()

	effect_prototypes.erase(effect_prototype)

#helper to find a specific running instance of a prototype on this unit
func get_effect_instance_by_prototype(proto: EffectPrototype) -> EffectInstance:
	#iterate through all schedules to find the instance
	for instance_array: Array in effects[proto.schedule].values():
		for instance: EffectInstance in instance_array:
			if instance.effect_prototype == proto:
					return instance
	return null

func get_effect_instances_by_prototype(proto: EffectPrototype) -> Array[EffectInstance]:
	var output: Array[EffectInstance] = []
	#iterate through all schedules to find the instance
	for schedule_dictionary: Dictionary in effects.values():
		for instance_array: Array in schedule_dictionary.values():
			for instance: EffectInstance in instance_array:
				if instance.effect_prototype == proto and not output.has(instance):
					output.append(instance)
	return output

func get_behavior_attribute(attribute_name: StringName) -> Variant: ##accesses properties for units, mainly for UI
	if not is_instance_valid(behavior):
		return null

	#check that the behavior actually implements the function before calling it.
	if behavior.has_method(&"get_display_data"):
		var data: Dictionary = behavior.get_display_data()
		#use .get() for a safe lookup that returns null if the key doesn't exist.
		return data.get(attribute_name, null)

	return null

func get_unit_state() -> void: ##used to refresh data about units, mainly for UI
	if is_instance_valid(health_component):
		UI.update_unit_health.emit(self, health_component.max_health, health_component.health)

func set_initial_behaviour_state(behavior_packet: Dictionary) -> void: ##preconfigure units before instantiation, used for environmental features with custom states (see terrain_expansion.gd)
	if not is_instance_valid(behavior):
		components_ready.connect(set_initial_behaviour_state.bind(behavior_packet), CONNECT_ONE_SHOT)
		return #wait until everything's ready

	for attribute: StringName in behavior_packet:
		if attribute in behavior:
			behavior[attribute] = behavior_packet[attribute]
		else:
			push_error(self, ": tried to apply behaviour modification of key: ", attribute, " but could not find matching behaviour attribute.")
	UI.update_unit_state.emit(self)

func take_hit(hit: HitData) -> void:
	if not is_instance_valid(self):
		return

	if not is_instance_valid(health_component): #this specifically catches the player core, which doesnt have a health
		return

	if is_zero_approx(health_component.health): #we're dead
		return

	hit.damage *= get_stat(Attributes.id.DAMAGE_TAKEN) as float
	hit.damage += get_stat(Attributes.id.FLAT_DAMAGE_TAKEN) as float

	hit.damage = maxf(hit.damage, 0.0)

	var evt: GameEvent = GameEvent.new()
	evt.event_type = GameEvent.EventType.HIT_RECEIVED
	evt.data = hit as HitData
	on_event.emit(evt) #trigger any local post-hit-received effects, accordingly mutate evt.data

	if hit.negate: #ignore negated hits
		return

	var damage: float = evt.data.damage
	var benchmark: float = health_component.health #NOTE: this indirect system of measurement is used due to custom setter functionality
	health_component.take_damage(damage, evt.data.breaking)
	#measure what happened
	var delta_health: float = benchmark - health_component.health #measure damage caused
	var unit_dead: bool = is_zero_approx(health_component.health) #are we dead?
	#compose a hit report, and send it to the source of the hit
	var hit_report := HitReportData.new()
	hit_report.copy_lineage_from(hit)
	hit_report.recursion = hit.recursion #NOTE: a hit and its corresponding report are of the SAME recursion
	hit_report.target = self
	hit_report.attack_id = hit.attack_id
	hit_report.velocity = hit.velocity
	if is_instance_valid(hit.source): hit_report.source = hit.source
	hit_report.damage_caused = delta_health
	hit_report.overkill = maxf(damage - benchmark, 0.0) if unit_dead else 0.0
	hit_report.statuses_applied = hit.status_effects.duplicate(true)

	if unit_dead and not is_zero_approx(delta_health):
		hit_report.death_caused = true

		ParticleManager.play_particles(ID.Particles.ENEMY_DEATH_SPARKS, self.global_position, hit_report.velocity.angle())

		died.emit(hit_report) #NOTE: this is when the unit dies
	elif graphics:
		ParticleManager.play_particles(ID.Particles.ENEMY_HIT_SPARKS, self.global_position, hit_report.velocity.angle())
		play_hit_flash()

	for modifier: Modifier in hit.modifiers:
		modifiers_component.add_modifier(modifier)

	for status: Attributes.Status in hit.status_effects:
		var stack: float = hit.status_effects[status].x
		var cooldown: float = hit.status_effects[status].y
		if stack <= 0.0: #refuse to process insignificant status effects (will crash if not done otherwise)
			continue
		modifiers_component.add_status(status, stack, cooldown, hit.source.unit_id if is_instance_valid(hit.source) else 0)

	var hit_report_evt := GameEvent.new()
	hit_report_evt.event_type = GameEvent.EventType.HIT_DEALT
	hit_report_evt.data = hit_report

	if not is_instance_valid(hit.source):
		return
	hit.source.on_event.emit(hit_report_evt) #cause source of hit to emit report

func deal_hit(hit: HitData, delivery_data : DeliveryData = null) -> void:
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

#this is a new virtual function that deals with actual death (connects to the died signal)
func on_killed(hit_report_data: HitReportData) -> void:
	Run.player.flux += hit_report_data.flux_value * 0.4 #reward player with flux
	Targeting.clear_damage(self) #clear any damage that might be locked on to us

	behavior.detach() #disable behavior
	for effect_prototype: EffectPrototype in effect_prototypes:
		remove_effect(effect_prototype) #detach effects

	if is_instance_valid(corpse_component):
		corpse_component.release_corpse(hit_report_data)

	queue_free()

func get_terrain_base() -> Terrain.Base: #retrieves terrain base at current position
	return Run.references.island.get_terrain_base(movement_component.cell_position)

func get_stat(attr: Attributes.id) -> Variant: #generic get stat function
	if health_component != null:
		if attr == Attributes.id.MAX_HEALTH or attr == Attributes.id.REGENERATION or attr == Attributes.id.REGEN_PERCENT or attr == Attributes.id.DAMAGE_TAKEN or attr == Attributes.id.FLAT_DAMAGE_TAKEN:
			return health_component.get_stat(modifiers_component, health_component.health_data, attr)

	if movement_component != null:
		if attr == Attributes.id.MAX_SPEED or attr == Attributes.id.ACCELERATION:
			return movement_component.get_stat(modifiers_component, movement_component.movement_data, attr)

	if attack_component != null:
		if attr == Attributes.id.DAMAGE or attr == Attributes.id.RADIUS or attr == Attributes.id.RANGE or attr == Attributes.id.COOLDOWN:
			return attack_component.get_stat(modifiers_component, attack_component.attack_data, attr)

	return null

func _draw() -> void:
	if not _DEBUG_DRAW:
		return

	if is_instance_valid(navigation_component) and not navigation_component._path.is_empty():
		if navigation_component._current_waypoint_index < navigation_component._path.size():
			var next_tile = navigation_component._path[navigation_component._current_waypoint_index]
			var next_pos = Island.cell_to_position(next_tile)
			draw_line(Vector2.ZERO, to_local(next_pos), Color(0, 0, 1, 0.5), 2.0)

	#2. visualize target (red/yellow line)
	if is_instance_valid(range_component):
		var target = range_component.get_target()
		if is_instance_valid(target):
			var local_target = to_local(target.global_position)

			#yellow = priority override (blocking tower)
			#red = normal target (closest/health/etc)
			var color: Color = Color(1,0,0,0.5)
			if range_component.priority_target_override == target:
				color = Color(1,1,0,0.5)

			draw_line(Vector2.ZERO, local_target, color, 3.0)
			draw_circle(local_target, 5.0, color)
