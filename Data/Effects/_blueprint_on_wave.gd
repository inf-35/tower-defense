extends EffectPrototype
class_name WaveBlueprintEffect

@export var params: Dictionary = {
	"blueprint_pool": [Towers.Type.TURRET, Towers.Type.FROST_TOWER, Towers.Type.CANNON, Towers.Type.BLUEPRINT_HARVESTER, Towers.Type.PALISADE],
}

var state: Dictionary = {}

func _handle_event(instance: EffectInstance, event: GameEvent):
	if event.event_type != GameEvent.EventType.WAVE_STARTED:
		return
		
	if instance.host.get_terrain_base() != Terrain.Base.RUINS:
		return
	
	assert(instance.params.has("blueprint_pool"))

	Player.add_blueprint(Blueprint.new(instance.params.blueprint_pool.pick_random()))
