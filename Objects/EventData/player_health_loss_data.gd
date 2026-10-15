extends EventData
class_name PlayerHealthLossData

signal resolved() ##runs follow-up reactions after health is committed, before the final death check

var health_before: float ##health before this loss; informational only
var health_after: float ##pending health; effects may change this to reduce loss or prevent death
