@abstract extends Resource
class_name EffectPrototype #used for cause-and-effect structures -> this is the mere effectprototype, to see runtime behaviour
#consult EffectInstance; for actual behaviour see sub-classes
#i.e. things like thorns

@export var effect_type: Effects.Type ##id of this type of effect
var global: bool = false ##whether this effect is a local(unit-wise) or global effect
var event_hooks: Array[GameEvent.EventType] ##all effects must have at least one, if NA put NONE

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
var stack_update_handler: Callable = _handle_stack_update

@export var icon: Texture2D ##icon that plays when this effectprototype is "triggered"
#event handlers; these are injected into EffectInstance at runtime
@abstract func _handle_attach(instance: EffectInstance) -> void
@abstract func _handle_detach(instance: EffectInstance) -> void
@abstract func _handle_event(instance: EffectInstance, event: GameEvent) -> void
func _handle_display_attach(instance: EffectInstance) -> void:
	pass
func _handle_stack_update(instance: EffectInstance) -> void:
	pass

func on_tick(instance: EffectInstance, delta: float) -> void:
	pass

func trigger_source_tower_pulse(instance: EffectInstance) -> void: ##plays the shared rite squash-stretch feedback on the rite tower responsible for a successful proc
	var source_tower: Tower = _resolve_source_tower(instance)
	if not is_instance_valid(source_tower):
		return

	source_tower.play_action_squash_stretch(Vector2(0.82, 1.2), Vector2(1.04, 0.98), 0.04, 0.08)

func _resolve_source_tower(instance: EffectInstance) -> Tower:
	if is_instance_valid(instance.source) and instance.source is Tower:
		return instance.source as Tower

	if is_instance_valid(instance.host) and instance.host is Tower and Towers.is_tower_rite((instance.host as Tower).type):
		return instance.host as Tower

	return null

func append_projectile_tint(hit_data: HitData, tint: Color) -> void: ##adds one projectile tint entry so multiple effects can cycle the base projectile visual without blending into a muddy color
	if not is_instance_valid(hit_data):
		return

	if tint.a <= 0.0:
		return

	hit_data.projectile_tints.append(tint)

@abstract func create_instance() -> EffectInstance

func return_generic_instance() -> EffectInstance: ##helper for child classes (returns most generic instance)
	var instance := EffectInstance.new()
	apply_generics(instance)
	#no persistent state needed
	return instance

func apply_generics(effect_instance: EffectInstance) -> void: ##helper for create_instance (applies generic values)
	effect_instance.global = global
	effect_instance.effect_type = effect_type
	effect_instance.event_hooks = event_hooks
	effect_instance.schedule = schedule
	#effect_instance.duration = duration
	effect_instance.effect_prototype = self as EffectPrototype

func get_save_data(effect_instance: EffectInstance) -> Dictionary:
	return {}

func load_save_data(effect_instance: EffectInstance, save_data: Dictionary) -> void:
	return
