class_name GameEvent

enum EventType {
	HIT_RECEIVED,
	PRE_HIT_DEALT,
	HIT_DEALT,
	PRE_HIT,
	HIT,
	WAVE_STARTED,
	
	ADJACENCY_UPDATED, #for towers only
}

var event_type: EventType
var data: EventData #mutable payload
