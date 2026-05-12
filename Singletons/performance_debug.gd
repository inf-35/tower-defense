extends RefCounted
class_name PerformanceDebug

const ENABLED: bool = false
const WINDOW_SIZE_FRAMES: int = 60

static var _window_start_frame: int = -1
static var _target_calls: int = 0
static var _target_time_usec: int = 0
static var _intercept_calls: int = 0
static var _intercept_time_usec: int = 0
static var _unit_effect_updates: int = 0
static var _unit_effect_time_usec: int = 0

static func _rotate_window() -> void:
	if not ENABLED:
		return

	var frame := Engine.get_process_frames()
	if _window_start_frame < 0:
		_window_start_frame = frame
		return

	var elapsed_frames := frame - _window_start_frame
	if elapsed_frames < WINDOW_SIZE_FRAMES:
		return

	print(
		"[PerfDebug] frames=", elapsed_frames,
		" target_calls=", _target_calls,
		" target_us=", _target_time_usec,
		" intercept_calls=", _intercept_calls,
		" intercept_us=", _intercept_time_usec,
		" unit_effect_updates=", _unit_effect_updates,
		" unit_effect_us=", _unit_effect_time_usec
	)

	_window_start_frame = frame
	_target_calls = 0
	_target_time_usec = 0
	_intercept_calls = 0
	_intercept_time_usec = 0
	_unit_effect_updates = 0
	_unit_effect_time_usec = 0

static func record_target_acquisition(duration_usec: int) -> void:
	if not ENABLED:
		return
	_rotate_window()
	_target_calls += 1
	_target_time_usec += duration_usec

static func record_intercept_prediction(duration_usec: int) -> void:
	if not ENABLED:
		return
	_rotate_window()
	_intercept_calls += 1
	_intercept_time_usec += duration_usec

static func record_unit_effect_update(duration_usec: int) -> void:
	if not ENABLED:
		return
	_rotate_window()
	_unit_effect_updates += 1
	_unit_effect_time_usec += duration_usec
