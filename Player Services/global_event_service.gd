extends Node
class_name GlobalEventService

#this service helps manage and centralise checks for global effects/events
#it is initialised and supervised by the player singleton

#structure: dictionary[schedule, dictionary[eventtype, array[effectinstance]]]
var _global_effects: Dictionary[int, Dictionary] = {}

#we keep a separate list of active instances for easier management/debugging
var _active_instances: Array[EffectInstance] = []
var _subscribers: Dictionary[GameEvent.EventType, Array] = {}

func subscribe(event_type: GameEvent.EventType, callback: Callable) -> void: ##registers one arbitrary global listener only for the requested event type
	if event_type == GameEvent.EventType.NONE or not callback.is_valid():
		return

	if not _subscribers.has(event_type):
		_subscribers[event_type] = [] as Array[Callable]

	var subscribers: Array[Callable] = _subscribers[event_type]
	if subscribers.has(callback):
		return

	subscribers.append(callback)

func subscribe_many(event_types: Array[GameEvent.EventType], callback: Callable) -> void: ##registers one arbitrary global listener for several concrete event types
	for event_type: GameEvent.EventType in event_types:
		subscribe(event_type, callback)

func unsubscribe(event_type: GameEvent.EventType, callback: Callable) -> void: ##removes one arbitrary listener from one global event bucket
	if not _subscribers.has(event_type):
		return

	var subscribers: Array[Callable] = _subscribers[event_type]
	subscribers.erase(callback)
	if subscribers.is_empty():
		_subscribers.erase(event_type)

func unsubscribe_many(event_types: Array[GameEvent.EventType], callback: Callable) -> void: ##removes one arbitrary listener from several global event buckets
	for event_type: GameEvent.EventType in event_types:
		unsubscribe(event_type, callback)

func is_subscribed(event_type: GameEvent.EventType, callback: Callable) -> bool: ##reports whether an exact global event subscription is active
	if not _subscribers.has(event_type):
		return false

	var subscribers: Array[Callable] = _subscribers[event_type]
	return subscribers.has(callback)

func publish(unit: Unit, game_event: GameEvent) -> void: ##runs global effects, then routes the mutable event only to listeners of its concrete type
	if not is_instance_valid(game_event):
		return
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"global_events_published")

	_dispatch_global_effects(game_event)
	if not _subscribers.has(game_event.event_type):
		return

	var subscribers: Array[Callable] = _subscribers[game_event.event_type]
	var dispatch_snapshot: Array[Callable] = subscribers.duplicate()
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"global_event_subscriber_callbacks", dispatch_snapshot.size())
	for callback: Callable in dispatch_snapshot:
		if not callback.is_valid():
			subscribers.erase(callback)
			continue
		callback.call(unit, game_event)

	if subscribers.is_empty():
		_subscribers.erase(game_event.event_type)

func get_subscriber_count(event_type: GameEvent.EventType) -> int: ##returns one typed bucket size for diagnostics without publishing an event
	if not _subscribers.has(event_type):
		return 0

	var subscribers: Array[Callable] = _subscribers[event_type]
	return subscribers.size()

func register_effect(prototype: EffectPrototype) -> EffectInstance: ##creates and indexes one global effect instance by schedule and authored event hooks
	var instance: EffectInstance = prototype.create_instance()

	instance.attach_global()
	var schedule: int = prototype.schedule

	#initialize dictionary path if missing
	if not _global_effects.has(schedule):
		_global_effects[schedule] = {}

	#sort the instance into buckets based on the events it listens to
	for event_type: GameEvent.EventType in prototype.event_hooks:
		if not _global_effects[schedule].has(event_type):
			_global_effects[schedule][event_type] = [] as Array[EffectInstance]

		_global_effects[schedule][event_type].append(instance)

	_active_instances.append(instance)
	return instance

func deregister_effect(instance: EffectInstance) -> void: ##detaches one global effect and removes it from every typed schedule bucket
	if not _active_instances.has(instance):
		return

	#trigger the detach handler logic
	instance.detach()

	#remove from the lookup buckets
	var schedule: int = instance.effect_prototype.schedule

	#we rely on the instance's own hooks to find where we put it
	for event_type: GameEvent.EventType in instance.event_hooks:
		if _global_effects.has(schedule) and _global_effects[schedule].has(event_type):
			_global_effects[schedule][event_type].erase(instance)

	#remove from active list
	_active_instances.erase(instance)
	instance.free()

func remove_effect_by_prototype(prototype: EffectPrototype) -> void: ##removes every active global instance created from one prototype
	#iterate backwards to safely remove while looping
	for i: int in range(_active_instances.size() - 1, -1, -1):
		var instance: EffectInstance = _active_instances[i]
		if instance.effect_prototype == prototype:
			deregister_effect(instance)

func get_effect_instance_by_prototype(prototype: EffectPrototype) -> EffectInstance: ##returns the first active global instance created from one prototype
	for active_instance: EffectInstance in _active_instances:
		if active_instance.effect_prototype == prototype:
			return active_instance

	return null

func _dispatch_global_effects(game_event: GameEvent) -> void: ##dispatches one global event through deterministic effect schedules before arbitrary listeners run
	var event_type: GameEvent.EventType = game_event.event_type
	#iterate through schedules in deterministic order (multiplicative -> additive -> reactive)
	for schedule: int in EffectPrototype.Schedule.values():
		if not _global_effects.has(schedule):
			continue

		var global_effects_of_schedule: Dictionary = _global_effects[schedule]

		#if no global effects care about this specific event type, skip
		if not global_effects_of_schedule.has(event_type):
			continue

		var effects_of_type: Array[EffectInstance] = global_effects_of_schedule[event_type]
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"global_effect_callbacks", effects_of_type.size())

		#iterate through global effects
		for global_effect: EffectInstance in effects_of_type:
			global_effect.handle_event_unfiltered(game_event)

func _process(_d: float) -> void: ##ticks active global effect prototypes on game time
	var delta: float = Clock.game_delta
	for instance: EffectInstance in _active_instances:
		instance.effect_prototype.on_tick(instance, delta)
