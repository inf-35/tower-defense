extends RefCounted
class_name GameEvent

enum EventType {
	PRE_HIT_DEALT, ##this happens right before we inflict a hit on others (attached with HitData)
	HIT_RECEIVED, ##this happens right after we get hit but before we process its effects (attached with HitData)
	HIT_DEALT, ##this happens after we inflict a hit on others (attached with HitReportData)
	DIED, ##special subset of hit dealt signals, fired just after hit_dealt (attached with HitReportData, but the emitter unit is the newly dead unit)
	REPLACED, ##fired when a unit is REPLACED by another, typically happens in upgrades (attached with UnitReplacedData)
	
	STATUS_ADDED, ##when a status is added
	STATUS_REMOVED, ##when a status is removed
	MODIFIER_ADDED, ##when a modifier is added
	MODIFIER_REMOVED, ##when a modifier is removed
	
	CHANGED_CELL, ##fires whenever any unit changes cells (attached with ChangedCellData)
	
	WAVE_STARTED, ##global wave start update (attached with WaveData)
	WAVE_ENDED, ##global wave end update (attached with WaveData)
	
	ADJACENCY_UPDATED, ##for towers only
	TOWER_BUILT, ##for when a tower is first built (attached with BuildTowerData)
}

var event_type: EventType
var data: EventData ##mutable payload
var unit: Unit ##the unit which emitted this event
