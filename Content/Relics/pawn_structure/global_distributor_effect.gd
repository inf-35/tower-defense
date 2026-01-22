extends EffectPrototype
class_name GlobalDistributorEffect

@export var effect_to_grant: EffectPrototype
@export var tower_type_filter: Towers.Type

class GlobalDistributorState extends RefCounted:
	var towers_affected: Dictionary[Tower, Modifier] = {}

func _init() -> void:
	event_hooks = [GameEvent.EventType.TOWER_BUILT]
	global = true
	
func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = GlobalDistributorState.new()
	return instance
	
func _handle_detach(instance: EffectInstance) -> void:
	var state := instance.state as GlobalDistributorState
	for tower: Tower in instance.state.towers_affected:
		tower.apply_effect(effect_to_grant, -1)
	
func _handle_attach(_i):
	# Scan all existing towers
	for t: Tower in References.root.get_tree().get_nodes_in_group(References.TOWER_GROUP):
		if t.type == tower_type_filter or tower_type_filter == Towers.Type.VOID:
			t.apply_effect(effect_to_grant)

func _handle_event(_i, event):
	if event.event_type == GameEvent.EventType.TOWER_BUILT:
		var t = event.data.tower
		if t.type == tower_type_filter or tower_type_filter == Towers.Type.VOID:
			t.apply_effect(effect_to_grant)
