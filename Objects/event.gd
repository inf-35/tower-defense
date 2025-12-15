class_name GameEvent

enum EventType {
	HIT_RECEIVED, ##this happens right after we get hit but before we process its effects (attached with HitData)
	PRE_HIT_DEALT, ##this happens right before we inflict a hit on others (attached with HitData)
	HIT_DEALT, ##this happens after we inflict a hit on others (attached with HitReportData)
	
	WAVE_STARTED, ##global wave start update
	
	ADJACENCY_UPDATED, #for towers only
}

var event_type: EventType
var data: EventData #mutable payload
