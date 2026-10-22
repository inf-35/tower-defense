extends Object
class_name EffectInstance #used for cause-and-effect structures -> this is the mere instance, to see actual data
#see EffectPrototype and its subclasses.

var effect_prototype: EffectPrototype ##effect prototype we're based off.

var source_id: int ##id of who spawned this
var effect_type: Effects.Type ##id of this type of effect
var schedule: EffectPrototype.Schedule
var event_hooks: Array[GameEvent.EventType]
var duration: float = -1.0 ##negative = permanent
var timer: Clock.GameTimer

var stacks: int = 0: ##how many stacks of this effect (mainly used for bookkeeping)
	set(ns):
		stacks = ns
		effect_prototype.stack_update_handler.call(self)
var enabled: bool = true

var state: RefCounted ##strategy delegate class that stores state information
#NOTE: all queryable information about the information should be stored within state
#or within effectprototype

const GLOBAL_RECURSION_LIMIT: int = 5 ##limit for effect recursion; see Unit effect parsing

var host: Unit ##to which unit does this effect apply onto
var source: Unit ##to which unit does this effect come from (may be null)
var global: bool = false ##whether this effect is a local(unit-wise) or global (game-wise) effect
var _is_removing: bool = false
var _runtime_attached: bool = false #authored scope does not imply that gameplay setup has run

func _init() -> void:
	pass

func mark_removing() -> void: ##disables this instance before structural removal runs on the host
	_is_removing = true
	enabled = false
	if is_instance_valid(timer):
		timer.is_active = false

func detach() -> void: ##runs gameplay cleanup at most once, and only after a gameplay attachment
	mark_removing()
	if not _runtime_attached:
		return
	_runtime_attached = false
	if global or is_instance_valid(host):
		effect_prototype.detach_handler.call(self)

func attach_to(_host: Unit) -> void: ##replaces an attachment while keeping prototype display setup outside the gameplay lifecycle
	detach()
	host = _host
	if not is_instance_valid(host):
		return
	_is_removing = false
	enabled = true

	if host.abstractive:
		effect_prototype._handle_display_attach(self)
		return
	_runtime_attached = true
	effect_prototype.attach_handler.call(self)

func attach_global() -> void: ##for attaching as a global effect
	detach()
	host = null
	_is_removing = false
	enabled = true
	_runtime_attached = true
	effect_prototype.attach_handler.call(self)

func handle_event_unfiltered(event: GameEvent = null) -> void: ##runs this already-indexed effect without repeating its event-type check
	if not enabled or not _runtime_attached:
		return
	if not global:
		if not is_instance_valid(host):
			return

	effect_prototype.event_handler.call(self, event)

func should_show_status_icon() -> bool: ##returns whether this runtime effect is eligible for hp-bar icon presentation
	return is_instance_valid(effect_prototype) and effect_prototype.show_as_status_icon and is_instance_valid(effect_prototype.icon)

func counts_as_status() -> bool: ##returns whether this attached effect participates in statuslike mechanics
	return enabled and stacks > 0 and is_instance_valid(effect_prototype) and effect_prototype.counts_as_status

func get_display_duration() -> float: ##returns remaining timed duration, or the authored permanent marker
	if is_instance_valid(timer) and timer.is_active:
		return maxf(timer.duration - timer.time_elapsed, 0.0)

	return duration

func refresh_duration(new_duration: float) -> void: ##starts or refreshes a game-time duration for temporary attached effects
	duration = new_duration
	if new_duration <= 0.0:
		notify_display_changed()
		return

	if is_instance_valid(timer) and timer.is_active:
		timer.time_elapsed = 0.0
		timer.duration = new_duration
	else:
		timer = Clock.create_game_timer(new_duration)
		timer.timeout.connect(_on_duration_timeout)

	notify_display_changed()

func notify_display_changed() -> void: ##asks the host unit to refresh this effect's hp-bar icon if it is displayable
	if _is_removing:
		return
	if not should_show_status_icon():
		return
	if not is_instance_valid(host):
		return

	host.effect_display_changed.emit(self, float(stacks), get_display_duration())

func _on_duration_timeout() -> void:
	if _is_removing or not enabled:
		return
	if not is_instance_valid(host):
		return

	mark_removing()
	host.remove_effect.call_deferred(effect_prototype)
