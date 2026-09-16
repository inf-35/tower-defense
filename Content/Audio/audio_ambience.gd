extends Node
class_name AudioAmbience

const BIRDSONG_DELAY_RANGE: Vector2 = Vector2(6.0, 15.0)
const WOODS_DELAY_RANGE: Vector2 = Vector2(3.0, 7.0)
const COMBAT_LOOP_START_VOLUME_DB: float = -50.0
const COMBAT_LOOP_TARGET_VOLUME_DB: float = -2.0
const AMBIENCE_BIRDSONG_VOLUME_RANGE: Vector2 = Vector2(-18.0, -16.0)
const AMBIENCE_WOODS_VOLUME_RANGE: Vector2 = Vector2(-16.0, -12.0)
const FADE_DURATION: float = 1.0

var combat_loop_stream: AudioStreamPlayer2D
var _birdsong_timer: Timer
var _woods_timer: Timer
var _combat_loop_fading_out: bool = false

##initializes persistent ambience timers and hooks run lifecycle signals when available
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ambience_timers()
	_connect_run_signals()
	_refresh_ambience_state()

##starts or stops ambience lanes according to the current run/menu state
func _refresh_ambience_state() -> void:
	if _should_play_combat_loop():
		start_combat_loop()
	else:
		end_combat_loop()

	if _should_play_woods_ambience():
		_start_woods_ambience()
	else:
		_stop_woods_ambience()

##fades in the combat loop when combat is active
func start_combat_loop() -> void:
	if is_instance_valid(combat_loop_stream) and combat_loop_stream.playing and not _combat_loop_fading_out:
		return

	_combat_loop_fading_out = false
	combat_loop_stream = Audio.play_sound(ID.Sounds.MUSIC_COMBAT_LOOP, COMBAT_LOOP_START_VOLUME_DB, Vector2.ZERO, false)
	if not is_instance_valid(combat_loop_stream):
		return

	combat_loop_stream.bus = &"Music"
	var tween := Audio.create_registered_audio_tween(combat_loop_stream)
	tween.tween_property(combat_loop_stream, "volume_db", COMBAT_LOOP_TARGET_VOLUME_DB, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.play()

##fades out the combat loop when combat is no longer active
func end_combat_loop() -> void:
	if not is_instance_valid(combat_loop_stream) or not combat_loop_stream.playing or _combat_loop_fading_out:
		return

	_combat_loop_fading_out = true
	var tween := Audio.create_registered_audio_tween(combat_loop_stream)
	tween.tween_property(combat_loop_stream, "volume_db", COMBAT_LOOP_START_VOLUME_DB, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.play()
	tween.finished.connect(func():
		if is_instance_valid(combat_loop_stream):
			Audio.stop_sound(combat_loop_stream)
		_combat_loop_fading_out = false
	)

##creates the two repeating one-shot timers used by woods ambience
func _create_ambience_timers() -> void:
	_birdsong_timer = _create_ambience_timer(_on_birdsong_timer_timeout)
	_woods_timer = _create_ambience_timer(_on_woods_timer_timeout)

##creates one real-time ambience timer connected to the given timeout callback
func _create_ambience_timer(timeout_callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_callback = Timer.TIMER_PROCESS_IDLE
	timer.timeout.connect(timeout_callback)
	add_child(timer)
	return timer

##connects to run lifecycle and phase signals without assuming a run already exists
func _connect_run_signals() -> void:
	if not Run.references_ready.is_connected(_on_run_references_ready):
		Run.references_ready.connect(_on_run_references_ready)
	if not Run.run_ending.is_connected(_on_run_ending):
		Run.run_ending.connect(_on_run_ending)
	_connect_phase_signals()

##connects to phase signals for the current run when phase state is available
func _connect_phase_signals() -> void:
	if not is_instance_valid(Run.phases):
		return
	if not Run.phases.combat_started.is_connected(_on_combat_started):
		Run.phases.combat_started.connect(_on_combat_started)
	if not Run.phases.building_phase_started.is_connected(_on_building_phase_started):
		Run.phases.building_phase_started.connect(_on_building_phase_started)
	if not Run.phases.phase_advanced.is_connected(_on_phase_advanced):
		Run.phases.phase_advanced.connect(_on_phase_advanced)

##disconnects from phase signals before the current run state is cleared
func _disconnect_phase_signals() -> void:
	if not is_instance_valid(Run.phases):
		return
	if Run.phases.combat_started.is_connected(_on_combat_started):
		Run.phases.combat_started.disconnect(_on_combat_started)
	if Run.phases.building_phase_started.is_connected(_on_building_phase_started):
		Run.phases.building_phase_started.disconnect(_on_building_phase_started)
	if Run.phases.phase_advanced.is_connected(_on_phase_advanced):
		Run.phases.phase_advanced.disconnect(_on_phase_advanced)

##refreshes ambience after a run finishes booting
func _on_run_references_ready() -> void:
	_connect_phase_signals()
	_refresh_ambience_state()

##returns ambience to menu-safe behavior after run teardown
func _on_run_ending() -> void:
	_disconnect_phase_signals()
	_refresh_ambience_state.call_deferred()

##starts combat ambience immediately because combat_started fires before current_phase mutates
func _on_combat_started(_wave_number: int) -> void:
	start_combat_loop()
	_stop_woods_ambience()

##restores woods ambience when returning to building prep
func _on_building_phase_started(_wave_number: int) -> void:
	_refresh_ambience_state()

##keeps ambience synchronized with choice, idle, game-over, and recursive phase changes
func _on_phase_advanced() -> void:
	_refresh_ambience_state()

##returns true when combat music should be audible
func _should_play_combat_loop() -> bool:
	if not Run.has_active_run() or not Run.is_run_ready() or not is_instance_valid(Run.phases):
		return false
	return Run.phases.current_phase == Phases.GamePhase.COMBAT_WAVE

##returns true when woods/menu ambience should be active
func _should_play_woods_ambience() -> bool:
	if not Run.has_active_run():
		return true
	if not Run.is_run_ready() or not is_instance_valid(Run.phases):
		return false
	if Run.current_game_environment != Run.GameEnvironment.WOODS:
		return false
	return Run.phases.current_phase == Phases.GamePhase.IDLE or Run.phases.current_phase == Phases.GamePhase.CHOICE or Run.phases.current_phase == Phases.GamePhase.BUILDING

##arms both woods ambience timers if they are not already running
func _start_woods_ambience() -> void:
	_schedule_timer_if_stopped(_birdsong_timer, BIRDSONG_DELAY_RANGE)
	_schedule_timer_if_stopped(_woods_timer, WOODS_DELAY_RANGE)

##stops both woods ambience timers
func _stop_woods_ambience() -> void:
	if is_instance_valid(_birdsong_timer):
		_birdsong_timer.stop()
	if is_instance_valid(_woods_timer):
		_woods_timer.stop()

##plays one birdsong sample if woods ambience is currently valid
func _on_birdsong_timer_timeout() -> void:
	if not _should_play_woods_ambience():
		return
	Audio.play_sound(ID.Sounds.AMBIENCE_BIRDSONG, randf_range(AMBIENCE_BIRDSONG_VOLUME_RANGE.x, AMBIENCE_BIRDSONG_VOLUME_RANGE.y))
	_schedule_ambience_timer(_birdsong_timer, BIRDSONG_DELAY_RANGE)

##plays one woods ambience sample if woods ambience is currently valid
func _on_woods_timer_timeout() -> void:
	if not _should_play_woods_ambience():
		return
	Audio.play_sound(ID.Sounds.AMBIENCE_WOODS, randf_range(AMBIENCE_WOODS_VOLUME_RANGE.x, AMBIENCE_WOODS_VOLUME_RANGE.y))
	_schedule_ambience_timer(_woods_timer, WOODS_DELAY_RANGE)

##starts a timer only when it is currently stopped
func _schedule_timer_if_stopped(timer: Timer, delay_range: Vector2) -> void:
	if not is_instance_valid(timer) or not timer.is_stopped():
		return
	_schedule_ambience_timer(timer, delay_range)

##schedules one ambience timer using its authored random delay range
func _schedule_ambience_timer(timer: Timer, delay_range: Vector2) -> void:
	var delay: float = randf_range(delay_range.x, delay_range.y)
	timer.start(maxf(delay, 0.1))
