extends EffectPrototype
class_name InterestEffect

@export var interest: float = 0.0 ##proportion of player flux earned as interest at the end of every wave
@export var interest_floor: float = 0.0 ##minimum interest
@export var interest_cap: float = 0.0 ##maximum interest

func _init():
	event_hooks = [GameEvent.EventType.WAVE_ENDED]
	global = true

func create_instance() -> EffectInstance:
	return return_generic_instance()

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(_instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.WAVE_ENDED:
		return
		
	Player.flux += clampf(Player.flux * interest, interest_floor, interest_cap)
