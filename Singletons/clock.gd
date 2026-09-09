extends Node
#Clock (autoload)

signal speed_changed(new_speed: float)

#--- private helper class for custom timers ---
class GameTimer:
	signal timeout
	var duration: float
	var time_elapsed: float = 0.0
	var is_active: bool = true
	var paused: bool = false

enum GameSpeed {
	PAUSE,
	BASE,
	FAST_FORWARD
}

const PAUSE_SPEED: float = 0.1
const BASE_SPEED: float = 1.0
const FAST_FORWARD_SPEED: float = 2.0

#--- public api ---
#this is the variable the ui will control (e.g., 1.0 for normal, 2.0 for double speed)
var speed_multiplier: float = BASE_SPEED:
	set(value):
		var clamped_value: float = max(0.0, value)
		if is_equal_approx(speed_multiplier, clamped_value):
			return
		speed_multiplier = clamped_value
		#if the multiplier is 0, pause the entire scene tree.
		get_tree().paused = is_zero_approx(speed_multiplier)
		speed_changed.emit(speed_multiplier)
#these are the values that game logic components will read each frame
var game_delta: float = 0.0 ##deltatime, adjusted for game speed
var physics_game_delta: float = 0.0 ##physics dT, adjusted for game speed

#--- private state ---
var _active_timers: Array[GameTimer] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UI.gamespeed_toggled.connect(func(gamespeed: GameSpeed):
		match gamespeed:
			GameSpeed.PAUSE:
				speed_multiplier = PAUSE_SPEED
			GameSpeed.BASE:
				speed_multiplier = BASE_SPEED
			GameSpeed.FAST_FORWARD:
				speed_multiplier = FAST_FORWARD_SPEED

		print("Clock: current gamespeed is ", speed_multiplier)
	)

func start() -> void:
	speed_multiplier = BASE_SPEED
	game_delta = 0.0
	physics_game_delta = 0.0
	_clear_timers()

#the main process loop calculates the scaled delta for game logic
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		speed_multiplier = PAUSE_SPEED
	elif Input.is_action_just_pressed("play"):
		speed_multiplier = BASE_SPEED
	elif Input.is_action_just_pressed("fast_forward"):
		speed_multiplier = FAST_FORWARD_SPEED

	game_delta = delta * speed_multiplier

	_advance_timers(game_delta)

func _advance_timers(delta: float) -> void: ##advances custom game-time timers and clears inactive timers from the hot path
	if _active_timers.is_empty():
		return

	for i: int in range(_active_timers.size() - 1, -1, -1):
		var timer: GameTimer = _active_timers[i]
		if not timer.is_active:
			if DebugAssistant.perf_instrumentation_active:
				DebugAssistant.record_perf_event(&"clock_timers_removed_inactive")
			_remove_timer_at(i)
			continue
		if timer.paused:
			continue

		timer.time_elapsed += delta
		if timer.time_elapsed < timer.duration:
			continue

		timer.is_active = false
		if DebugAssistant.perf_instrumentation_active:
			DebugAssistant.record_perf_event(&"clock_timers_expired")
		_remove_timer_at(i)
		timer.timeout.emit()

func _remove_timer_at(index: int) -> void: ##removes a timer without shifting the rest of the array on every expired entry
	var last_index: int = _active_timers.size() - 1
	if index != last_index:
		_active_timers[index] = _active_timers[last_index]
	_active_timers.pop_back()

func _clear_timers() -> void: ##drops timers from the previous run/session when the game clock is restarted
	for timer: GameTimer in _active_timers:
		timer.is_active = false
	_active_timers.clear()

#the physics process loop does the same for physics-based logic
func _physics_process(delta: float) -> void:
	physics_game_delta = delta * speed_multiplier

#--- public timer api ---
#this is the new function that any system will call to create a game-speed-aware timer.
#it returns a signal that the calling code can 'await'.
func create_game_timer(duration: float) -> GameTimer:
	var timer := GameTimer.new()
	timer.duration = duration
	_active_timers.append(timer)
	if DebugAssistant.perf_instrumentation_active:
		DebugAssistant.record_perf_event(&"clock_timers_created")
	return timer

func await_game_time(duration: float) -> Signal:
	return create_game_timer(duration).timeout
