extends EffectPrototype
class_name WaveBlueprintEffect

@export var params: Dictionary = {
	"blueprint_type": Towers.Type.DPS_TOWER,
}

func _handle_event(instance: EffectInstance, event: GameEvent):
	if event.event_type != GameEvent.EventType.WAVE_STARTED:
		return
		
	if instance.host.get_terrain_base() != Terrain.Base.RUINS:
		print("wrong terrain type.")
		return
	
	assert(instance.params.has("blueprint_type"))

	Player.blueprints.append(Blueprint.new(params.blueprint_type))
	print("new blueprint!")
