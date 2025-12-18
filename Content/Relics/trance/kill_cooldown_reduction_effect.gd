extends EffectPrototype
class_name KillCooldownReductionEffect

@export var require_status: bool = true
@export var required_status: Attributes.Status = Attributes.Status.CURSED
@export var required_threshold: float = 0.0
@export var cooldown_multiplier: float = 0.5 ## multiplier applied to remaining cooldown (0.5 = halve it)

func _init() -> void:
	event_hooks = [GameEvent.EventType.DIED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance
	
func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return
	
	var hit_report := event.data as HitReportData
	if not hit_report:
		return

	var victim: Unit = hit_report.target
	if require_status:
		if not is_instance_valid(victim) or not is_instance_valid(victim.modifiers_component):
			return
			
		if not victim.modifiers_component.has_status(required_status, required_threshold):
			return

	var killer: Unit = hit_report.source
	# esure the killer actually has an attack component to modify (and exists)
	if is_instance_valid(killer) and is_instance_valid(killer.attack_component):
		# directly modify the local variable as requested
		killer.attack_component.current_cooldown *= cooldown_multiplier
