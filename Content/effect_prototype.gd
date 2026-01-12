@abstract extends Resource
class_name EffectPrototype #used for cause-and-effect structures -> this is the mere effectprototype, to see runtime behaviour 
#consult EffectInstance; for actual behaviour see sub-classes
#i.e. things like thorns

@export var effect_type: Effects.Type ##id of this type of effect
var global: bool = false ##whether this effect is a local(unit-wise) or global effect
var event_hooks: Array[GameEvent.EventType] #just for information, the event hooks can be found in per-handler behaviour

enum Schedule { #schedule categories, used to enforce determinstic ordering of effects
	MULTIPLICATIVE,
	ADDITIVE,
	REACTIVE,
}

@export var schedule: Schedule = Schedule.REACTIVE #NOTE: schedule is a purely effect_prototype-handled variable
#this means its impossible to modify schedule at runtime
#inject handler functions into EffectInstance
var attach_handler: Callable = _handle_attach
var detach_handler: Callable = _handle_detach
var event_handler: Callable = _handle_event

#event handlers; these are injected into EffectInstance at runtime
@abstract func _handle_attach(instance: EffectInstance) -> void
@abstract func _handle_detach(instance: EffectInstance) -> void
@abstract func _handle_event(instance: EffectInstance, event: GameEvent) -> void

func on_tick(instance: EffectInstance, delta: float) -> void:
	pass

@abstract func create_instance() -> EffectInstance

func return_generic_instance() -> EffectInstance: ##helper for child classes (returns most generic instance)
	var instance := EffectInstance.new()
	apply_generics(instance)
	# no persistent state needed
	return instance

func apply_generics(effect_instance: EffectInstance) -> void: ##helper for create_instance (applies generic values)
	effect_instance.global = global
	effect_instance.effect_type = effect_type
	effect_instance.event_hooks = event_hooks
	#effect_instance.duration = duration
	effect_instance.effect_prototype = self as EffectPrototype
