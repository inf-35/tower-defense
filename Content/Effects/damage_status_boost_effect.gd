extends EffectPrototype
class_name DamageStatusBoostEffect

@export var required_status: Attributes.Status = Attributes.Status.BURN ##status the damaged unit must currently have
@export var required_status_stacks: float = 0.0 ##minimum status stacks required; zero accepts any positive amount
@export var damage_threshold: float = 0.0 ##incoming damage must be strictly greater than this value before the boost applies
@export var damage_multiplier: float = 2.0 ##multiplier applied to qualifying damage; 2.0 is +100% damage
@export var hostile_targets_only: bool = true ##when true, allied and neutral recipients cannot receive the damage boost
@export var proc_vfx: VFXInfo ##optional aoe particle field played on the recipient when the damage boost applies
@export var proc_vfx_radius: float = 10.0 ##world-space radius used by the optional qualifying-hit particle field

func _init() -> void: ##registers a stateless global modifier for incoming damage payloads
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance: ##creates a stateless global effect instance
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##multiplies a qualifying hit before the recipient processes its damage
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var hit_data: HitData = event.data as HitData
	var victim: Unit = event.unit
	if not hit_data or hit_data.negate or not is_instance_valid(victim):
		return
	if hostile_targets_only and not victim.hostile:
		return
	if hit_data.damage <= damage_threshold:
		return
	if not is_instance_valid(victim.modifiers_component):
		return
	var status_stacks: float = victim.modifiers_component.get_status_count(required_status)
	if status_stacks <= 0.0 or status_stacks < required_status_stacks:
		return

	hit_data.damage *= _get_damage_multiplier(instance)
	if is_instance_valid(proc_vfx):
		VFXManager.play_aoe_field(proc_vfx, victim.global_position, proc_vfx_radius)

func _get_damage_multiplier(instance: EffectInstance) -> float: ##composes duplicate effect stacks as additive copies of the authored bonus
	var effect_stacks: int = maxi(instance.stacks, 1)
	return 1.0 + ((damage_multiplier - 1.0) * float(effect_stacks))
