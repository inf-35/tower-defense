extends Node
class_name UnitComponent
#abstract class for all unit components

@onready var unit : Unit = get_parent()

var _stagger: int = 0
var _STAGGER_CYCLE: int = 3
var _accumulated_delta: float = 0.0

func initiate():
	pass

func _ready():
	_stagger += randi_range(0, _STAGGER_CYCLE)
	
func get_stat(effects_component: EffectsComponent, data: Data, attribute: Attributes.id) -> Variant:
	return data.get(Data.get_stringname(attribute)) if (effects_component == null or effects_component.pull_stat(attribute) == null) else effects_component.pull_stat(attribute) 
