extends EffectPrototype
class_name WeregildEffect

@export var sell_value_proportion: float = 0.1 ##proportion of sell value paid whenever an allied tower takes a real hit

func _init() -> void:
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var tower: Tower = event.unit as Tower
	if not is_instance_valid(tower) or tower.hostile or tower.environmental:
		return

	var hit_data: HitData = event.data as HitData
	if not hit_data or hit_data.negate or hit_data.damage <= 0.0:
		return

	var sell_value: float = Towers.get_tower_refund_value(tower.type) * Tower.REFUND_PROPORTION
	Run.player.flux += sell_value * sell_value_proportion * _get_effect_stacks(instance)

func _get_effect_stacks(instance: EffectInstance) -> int:
	return maxi(instance.stacks, 1)
