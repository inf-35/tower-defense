extends Node
class_name GlobalEventService
#this service helps manage and centralise checks for global effects/events. is 
#initialised and supervised by the Player singleton.
#NOTE: why centralise? be centralising conditional checks 


#state
var _global_effects: Dictionary[EffectPrototype.Schedule, Dictionary] = {
	#each dictionary is of Dictionary[GameEvent.EventType, Array[GlobalEffect]]
}

func initialise_event_bus(event_bus_signal: Signal) -> void: #called by Player
	#where event bus signal contains the parameters unit: Unit, game_event: GameEvent (see Player)
	event_bus_signal.connect(_handle_event)
	
func _handle_event(unit: Unit, game_event: GameEvent) -> void:
	var event_type: GameEvent.EventType = game_event.event_type
	
	for schedule: int in EffectPrototype.Schedule:
		if not _global_effects.has(schedule):
			_global_effects[schedule] = {} #create a placeholder dictionary
		
		var global_effects_of_schedule: Dictionary = _global_effects[schedule]
		if not global_effects_of_schedule.has(event_type):
			continue
		
		for global_effect in global_effects_of_schedule[event_type]: #iterate through global effects
			global_effect.handle_event(unit, game_event)
	
