class_name GameEvent

enum EventType {
	HIT_RECEIVED,
	PRE_HIT_DEALT,
	HIT_DEALT,
	PRE_HIT,
	HIT,
	WAVE_STARTED,
	
	ADJACENCY_UPDATED, #for towers only
	ENVIRONMENT_CHANGED, #for towers only
	CAPACITY_FORCE_UPDATE, #for capacity generation
}

var event_type: EventType
var data: EventData #mutable payload
