extends EffectPrototype
class_name MacuahuitlEffect

@export var required_element: Towers.Element = Towers.Element.KINETIC
@export var trigger_count: int = 4
@export var bleed_stacks_added: float = 2.0
@export var bleed_duration: float = 2.0 # default duration if none exists

class CounterState extends RefCounted:
	var attack_count: int = 0

func _init() -> void:
	# PRE_HIT_DEALT allows modifying the hit before it flies
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = CounterState.new()
	return instance

func _handle_attach(_i: EffectInstance) -> void: pass
func _handle_detach(_i: EffectInstance) -> void: pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT:
		return
		
	# validate source
	var source: Unit = event.unit
	if not is_instance_valid(source) or not source is Tower:
		return
	if source.hostile:
		return
		
	# check element
	if Towers.get_tower_element(source.type) != required_element:
		return

	var state := instance.state as CounterState
	state.attack_count += 1

	if state.attack_count >= trigger_count:
		state.attack_count = 0
		_apply_bonus(event.data as HitData)

func _apply_bonus(hit_data: HitData) -> void:
	if not hit_data: return

	# add bleed stacks
	var current: Vector2 = hit_data.status_effects.get(Attributes.Status.BLEED, Vector2.ZERO)
	current.x += bleed_stacks_added
	current.y = max(current.y, bleed_duration)
		
	hit_data.status_effects[Attributes.Status.BLEED] = current
