extends Resource
class_name Effect #used for cause-and-effect structures
#i.e. things like thorns

var source_id: int
var event_hooks: Array[GameEvent.EventType]
var duration: float = -1.0 #negative = permanent

func _init():
	pass

func handle_event(event: GameEvent):
	pass #override in sub-classes
