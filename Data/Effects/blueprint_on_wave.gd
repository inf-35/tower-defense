extends EffectPrototype
class_name WaveBlueprintEffect

@export var params: Dictionary = {
	"blueprint_pool": [Towers.Type.TURRET],
}

func _handle_event(instance: EffectInstance, event: GameEvent):
	if event.event_type != GameEvent.EventType.WAVE_STARTED:
		return
		
	if instance.host.get_terrain_base() != Terrain.Base.RUINS:
		print("wrong terrain type.")
		return
	
	assert(instance.params.has("blueprint_pool"))

	Player.blueprints.append(Blueprint.new(instance.params.blueprint_pool.pick_random()))
	print("new blueprint!")
