extends Node
class_name Behavior

# this will be the unit "chassis" that owns this behavior
var unit: Unit

# references to the unit's other components, injected by the unit itself
var modifiers_component: ModifiersComponent
var health_component: HealthComponent
var movement_component: MovementComponent
var navigation_component: NavigationComponent
var range_component: RangeComponent
var attack_component: AttackComponent
var animation_player: AnimationPlayer

var graphics: Node2D
var turret: Node2D
#generic "timer" variable
var _cooldown: float = 0.0 ##NOTE: this is not the attack cooldown, which can be found in AttackComponent

func initialise(host_unit: Unit): ##his function is called by the unit to give the behavior all the tools it needs
	set_process(false)
	
	self.unit = host_unit
	# safely get references
	self.modifiers_component = unit.modifiers_component
	self.health_component = unit.health_component
	self.movement_component = unit.movement_component
	self.navigation_component = unit.navigation_component
	self.range_component = unit.range_component
	self.attack_component = unit.attack_component
	self.animation_player = unit.animation_player
	
	self.graphics = unit.graphics
	if &"turret" in unit:
		self.turret = unit.turret
		
	if unit.abstractive:
		return

	start()
	
	unit.on_event.connect(func(event: GameEvent):
		if event.event_type == GameEvent.EventType.WAVE_STARTED:
			_cooldown = 0.0 #reset timer upon wave starting
		
		if event.event_type == GameEvent.EventType.HIT_RECEIVED:
			_play_animation(&"hit")
			
		if event.event_type == GameEvent.EventType.REPLACED: #handle transfer to new unit behavior
			var data := event.data as UnitReplacedData
			if data.old_unit == unit:
				if is_instance_valid(data.new_unit.behavior):
					transfer_state(data.new_unit.behavior)
	)

func detach(): ##function called when the unit wants to detach this behavior (i.e. upon death)
	pass
	
func attach(): ##function called when the unit wants to reattach this handler (i.e. tower resurrection)
	pass

func transfer_state(new_behavior: Behavior): ##called when we want to transfer state to another behavior (i.e. upgrading)
	new_behavior._cooldown = _cooldown

func start() -> void: ##behavior start function, called at the start of behavior when the unit is created or revived
	#by default units try to navigate to the origin
	_attempt_navigate_to_origin()

func update(delta: float) -> void: ##main update loop; delta is already game delta
	# this virtual function will be overridden by concrete behaviors
	_cooldown += delta
	_attempt_simple_attack()

# this virtual function is the new, generic entrypoint for the UI to query
# custom data from a behavior. concrete behaviors should override this.
func get_display_data() -> Dictionary:
	return {} # return an empty dictionary by default

func draw_visuals(canvas: RangeIndicator) -> void: #see RangeIndicator
	var tower := unit as Tower
	if not tower.get_stat(Attributes.id.RANGE):
		return
	canvas.draw_circle(tower.global_position, tower.get_stat(Attributes.id.RANGE), canvas.range_color, false, 1.0)
	
# a helper function for safe animation playback
func _play_animation(anim_name: StringName, custom_speed: float = 1.0) -> void:
	if is_instance_valid(animation_player) and animation_player.has_animation(anim_name):
		animation_player.play(anim_name, -1, custom_speed * Clock.speed_multiplier, custom_speed < 0.0)

#helper functions for child classes to use
func _is_attack_possible() -> bool:
	if attack_component == null or range_component == null:
		return false
	
	if unit.disabled:
		return false
		
	if unit.attack_only_when_blocked and not unit.blocked:
		return false
	
	#print(attack_component, " ", attack_component.attack_data)
	if attack_component.current_cooldown <= 0.0:
		var target = range_component.get_target() as Unit
		if target:
			return true

	return false

func _attempt_simple_attack() -> bool:
	if not _is_attack_possible():
		return false
		
	var target = range_component.get_target() as Unit
	if target:
		#print(_cooldown, " ", attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN))
		attack_component.attack(target)
		unit.queue_redraw()
		return true
		
	return false

func _attempt_navigate_to_origin() -> bool:
	if not is_instance_valid(navigation_component):
		return false
	
	navigation_component.goal = Vector2i.ZERO
	return true
