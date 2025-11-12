class_name GameEvent

enum EventType {
	HIT_RECEIVED, ##this happens right after we get hit
	PRE_HIT_DEALT, ##this happens right before we inflict a hit on others
	HIT_DEALT, ##this happens after we inflict a hit on others (attached with HitReportData)
	WAVE_STARTED,
	
	ADJACENCY_UPDATED, #for towers only
	ENVIRONMENT_CHANGED, #for towers only
	CAPACITY_FORCE_UPDATE, #for capacity generation
}

var event_type: EventType
var data: EventData #mutable payload
