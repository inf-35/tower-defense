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
#generic "timer" variable
var _cooldown: float = 0.0

# this function is called by the unit to give the behavior all the tools it needs
func initialise(host_unit: Unit):
	self.unit = host_unit
	# safely get references
	self.modifiers_component = unit.modifiers_component
	self.health_component = unit.health_component
	self.movement_component = unit.movement_component
	self.navigation_component = unit.navigation_component
	self.range_component = unit.range_component
	self.attack_component = unit.attack_component
	start()

#behavior start function, called at the start of behavior
func start() -> void:
	#by default units try to navigate to the origin
	_attempt_navigate_to_origin()

# this is the main update loop, called by the unit's _process function
func update(delta: float) -> void:
	# this virtual function will be overridden by concrete behaviors
	_cooldown += delta
	_attempt_attack()

# this virtual function is the new, generic entrypoint for the UI to query
# custom data from a behavior. concrete behaviors should override this.
func get_display_data() -> Dictionary:
	return {} # return an empty dictionary by default

#helper functions for child classes to use
func _attempt_attack() -> bool:
	if attack_component == null or range_component == null:
		return false
	
	if unit.disabled:
		return false
		
	if unit.attack_only_when_blocked and not unit.blocked:
		return false
		
	if _cooldown >= attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN):

		var target = range_component.get_target() as Unit
		if target:
			#print(_cooldown, " ", attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN))
			attack_component.attack(target)
			_cooldown = 0.0
			unit.queue_redraw()
			return true
			
	return false

func _attempt_navigate_to_origin() -> bool:
	if not is_instance_valid(navigation_component):
		return false
	
	navigation_component.goal = Vector2i.ZERO
	return true
