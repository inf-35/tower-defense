class_name GameEvent

enum EventType {
	HIT_RECEIVED,
	PRE_HIT_DEALT,
	HIT_DEALT,
	PRE_HIT,
	HIT
}

var event_type: EventType
var source: Node #who is agent
var target: Node #who is affected
var data: Dictionary #mutable payload
