extends EffectPrototype
class_name ClubRiteEffect

@export var chance: float = 0.05
@export var duration: float = 1.0

func _init() -> void:
	event_hooks = [GameEvent.EventType.PRE_HIT_DEALT]

func create_instance() -> EffectInstance:
	var i = EffectInstance.new()
	apply_generics(i)
	return i

func _handle_attach(_i): pass
func _handle_detach(_i): pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.PRE_HIT_DEALT: return
	
	var hit_data = event.data as HitData
	if not hit_data: return
	
	# Check chance (scaled by stacks? 5% * stacks)
	if randf() > (chance * instance.stacks): return
	
	# Inject Stun
	hit_data.status_effects[Attributes.Status.STUN] = Vector2(1.0, duration)
