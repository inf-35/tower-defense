@abstract
extends Node
class_name UnitComponent
#abstract class for all unit components

@onready var unit : Unit = get_parent()
#stagger system --- for components that dont need to run every frame
var _stagger: int = 0
var _STAGGER_CYCLE: int = 3
var _accumulated_delta: float = 0.0
#stat cache system
var stat_cache: Dictionary[Attributes.id, Variant] = {} #keys are Attributes.id

func initiate():
	pass

func _ready():
	_stagger = randi_range(0, _STAGGER_CYCLE)

func create_stat_cache(modifiers_component: ModifiersComponent, needed_stats: Array[Attributes.id] = []) -> void:
	for attr: Attributes.id in needed_stats:
		if modifiers_component.has_stat(attr):
			stat_cache[attr] = modifiers_component.pull_stat(attr)

	modifiers_component.stat_changed.connect(func(attr: Attributes.id):
		if needed_stats.has(attr): #we already know we have the prereqs
			stat_cache[attr] = modifiers_component.pull_stat(attr)
	)
	
func get_stat(modifiers_component: ModifiersComponent, data: Data, attribute: Attributes.id) -> Variant:
	if stat_cache.has(attribute):
		return stat_cache[attribute]
	else:
		return get_stat_raw(modifiers_component, data, attribute)
		
func get_stat_raw(modifiers_component: ModifiersComponent, data: Data, attribute: Attributes.id) -> Variant:
	if not data:
		push_warning("no data found in ", self, ", unit: ", unit)
		return 0.0
	return data.get(Data.get_stringname(attribute)) if (modifiers_component == null or modifiers_component.pull_stat(attribute) == null) else modifiers_component.pull_stat(attribute) 

@abstract func get_save_data()
