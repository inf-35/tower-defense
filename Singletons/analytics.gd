extends Node

class RunRecord extends RefCounted:
	var run_id: String = ""
	var started_from_save: bool = false
	var segment_started_ticks_msec: int = 0
	var accumulated_run_seconds: float = 0.0
	var max_wave_reached: int = 0
	var tower_counts: Dictionary[String, int] = {}
	var relic_counts: Dictionary[String, int] = {}
	var rite_counts: Dictionary[String, int] = {}
	var finalized: bool = false
	var live: bool = false

@export var enabled: bool = false ##master toggle for outbound analytics requests
@export var endpoint_url: String = "" ##https endpoint that receives one json event per request
@export var shared_secret: String = "" ##optional shared secret copied into each outbound payload
@export var queue_save_path: String = "user://analytics_queue.json" ##local retry queue for failed desktop requests and interrupted sessions
@export var request_timeout_seconds: float = 8.0 ##desktop request timeout in seconds
@export var game_name_override: String = "" ##optional override for the project name used in outbound payloads
@export var send_session_snapshot_on_run_end: bool = true ##captures coarse global session progress without a separate wave-event stream
@export var verbose_logging: bool = false ##prints local analytics activity for setup/debugging

@export var http_request: HTTPRequest
@export var retry_timer: Timer

const EVENT_RUN_SUMMARY: String = "run_summary"
const EVENT_SESSION_SNAPSHOT: String = "session_snapshot"
const EVENT_SESSION_SUMMARY: String = "session_summary"
const GOOGLE_SCRIPT_ENDPOINT_HINT: String = "script.google.com/macros/"
const RETRY_DELAY_SECONDS: float = 12.0

var _pending_events: Array[Dictionary] = []
var _request_in_flight: bool = false
var _session_end_queued: bool = false

var _session_id: String = ""
var _session_started_ticks_msec: int = 0
var _session_runs_started: int = 0
var _session_runs_resumed: int = 0
var _session_runs_completed: int = 0

var _current_run: RunRecord
var _tracked_player: Player
var _tracked_phases: Phases

func _ready() -> void:
	_session_started_ticks_msec = Time.get_ticks_msec()
	_session_id = _make_ephemeral_id("session")

	if is_instance_valid(http_request) and not http_request.request_completed.is_connected(_on_request_completed):
		http_request.timeout = request_timeout_seconds
		http_request.request_completed.connect(_on_request_completed)
	if is_instance_valid(retry_timer) and not retry_timer.timeout.is_connected(_try_send_next):
		retry_timer.wait_time = RETRY_DELAY_SECONDS
		retry_timer.one_shot = true
		retry_timer.timeout.connect(_try_send_next)

	Run.references_ready.connect(_on_run_ready)
	Run.run_ending.connect(_on_run_ending)
	RewardService.reward_applied.connect(_on_reward_applied)
	UI.display_game_over.connect(_on_game_over_displayed)

	_load_queue()
	_try_send_next()

func begin_run(is_loading_save: bool) -> void: ##called once island boot knows whether this scene is a fresh run or a resumed save
	if _has_unfinalized_run():
		if is_loading_save:
			_session_runs_resumed += 1
			_current_run.started_from_save = true
			_current_run.segment_started_ticks_msec = Time.get_ticks_msec()
			_current_run.live = true
			return
		_finalize_current_run("abandon", "replaced_by_new_run")

	if is_loading_save:
		_session_runs_resumed += 1
	else:
		_session_runs_started += 1

	_current_run = _make_run_record(is_loading_save)

func get_save_data() -> Dictionary:
	if not _has_unfinalized_run():
		return {}

	return {
		"run_id": _current_run.run_id,
		"started_from_save": _current_run.started_from_save,
		"accumulated_run_seconds": _get_current_run_duration_seconds(),
		"max_wave_reached": _current_run.max_wave_reached,
		"tower_counts": _copy_int_dictionary(_current_run.tower_counts),
		"relic_counts": _copy_int_dictionary(_current_run.relic_counts),
		"rite_counts": _copy_int_dictionary(_current_run.rite_counts),
	}

func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return

	_current_run = RunRecord.new()
	_current_run.run_id = str(data.get("run_id", _make_ephemeral_id("run")))
	_current_run.started_from_save = bool(data.get("started_from_save", true))
	_current_run.segment_started_ticks_msec = Time.get_ticks_msec()
	_current_run.accumulated_run_seconds = float(data.get("accumulated_run_seconds", 0.0))
	_current_run.max_wave_reached = int(data.get("max_wave_reached", 0))
	_current_run.tower_counts = _load_int_dictionary(data.get("tower_counts", {}))
	_current_run.relic_counts = _load_int_dictionary(data.get("relic_counts", {}))
	_current_run.rite_counts = _load_int_dictionary(data.get("rite_counts", {}))
	_current_run.finalized = false
	_current_run.live = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_queue_session_end_once("app_close")

func _exit_tree() -> void:
	_queue_session_end_once("app_close")

func _on_run_ready() -> void:
	_disconnect_runtime_hooks()
	if not _has_unfinalized_run():
		return

	if is_instance_valid(Run.player):
		_tracked_player = Run.player
		if not _tracked_player.tower_placed.is_connected(_on_tower_placed):
			_tracked_player.tower_placed.connect(_on_tower_placed)

	if is_instance_valid(Run.phases):
		_tracked_phases = Run.phases
		if not _tracked_phases.wave_cycle_started.is_connected(_on_wave_cycle_started):
			_tracked_phases.wave_cycle_started.connect(_on_wave_cycle_started)
		_current_run.max_wave_reached = maxi(_current_run.max_wave_reached, _tracked_phases.current_wave_number)

func _on_run_ending() -> void:
	_disconnect_runtime_hooks()
	if not _has_unfinalized_run():
		return

	_current_run.accumulated_run_seconds = _get_current_run_duration_seconds()
	_current_run.live = false

	if SaveLoad.has_save_file():
		_persist_queue()
		return

	_finalize_current_run("abandon", "run_ended_without_resolution")

func _on_tower_placed(tower_type: Towers.Type, _tower: Tower) -> void:
	if not _has_unfinalized_run():
		return
	_increment_count(_current_run.tower_counts, _tower_key_from_type(tower_type))

func _on_wave_cycle_started(wave_number: int) -> void:
	if not _has_unfinalized_run():
		return
	_current_run.max_wave_reached = maxi(_current_run.max_wave_reached, wave_number)

func _on_reward_applied(reward: Reward) -> void:
	if not _has_unfinalized_run():
		return

	match reward.type:
		Reward.Type.ADD_RELIC:
			if is_instance_valid(reward.relic):
				_increment_count(_current_run.relic_counts, _relic_key_from_data(reward.relic))
		Reward.Type.ADD_RITE:
			_increment_count(_current_run.rite_counts, _tower_key_from_type(reward.rite_type))

func _on_game_over_displayed(is_victory: bool) -> void:
	if not _has_unfinalized_run():
		return
	_finalize_current_run("victory" if is_victory else "defeat", "game_over")

func _finalize_current_run(result: String, reason: String) -> void: ##builds one terminal run summary and one coarse session snapshot, then marks the run immutable
	if not _has_unfinalized_run():
		return

	_current_run.accumulated_run_seconds = _get_current_run_duration_seconds()
	_current_run.live = false
	_current_run.finalized = true
	_session_runs_completed += 1

	var current_wave_number: int = Run.phases.current_wave_number if is_instance_valid(Run.phases) else _current_run.max_wave_reached
	var payload: Dictionary = {
		"run_id": _current_run.run_id,
		"result": result,
		"result_reason": reason,
		"started_from_save": _current_run.started_from_save,
		"difficulty": _difficulty_key(Run.current_game_difficulty),
		"environment": _environment_key(Run.current_game_environment),
		"run_duration_seconds": int(round(_current_run.accumulated_run_seconds)),
		"max_wave_reached": _current_run.max_wave_reached,
		"final_wave_number": current_wave_number,
		"session_duration_seconds": _get_session_duration_seconds(),
		"session_runs_started": _session_runs_started,
		"session_runs_resumed": _session_runs_resumed,
		"session_runs_completed": _session_runs_completed,
		"placed_tower_counts": _copy_int_dictionary(_current_run.tower_counts),
		"collected_relic_counts": _copy_int_dictionary(_current_run.relic_counts),
		"collected_rite_counts": _copy_int_dictionary(_current_run.rite_counts),
	}
	_enqueue_event(EVENT_RUN_SUMMARY, payload)

	if send_session_snapshot_on_run_end:
		_queue_session_snapshot("run_end", EVENT_SESSION_SNAPSHOT)

func _queue_session_snapshot(reason: String, event_type: String) -> void:
	var payload: Dictionary = {
		"snapshot_reason": reason,
		"session_duration_seconds": _get_session_duration_seconds(),
		"session_runs_started": _session_runs_started,
		"session_runs_resumed": _session_runs_resumed,
		"session_runs_completed": _session_runs_completed,
		"active_run_id": _current_run.run_id if _has_unfinalized_run() else "",
	}
	_enqueue_event(event_type, payload)

func _queue_session_end_once(reason: String) -> void:
	if _session_end_queued:
		return
	_session_end_queued = true
	_queue_session_snapshot(reason, EVENT_SESSION_SUMMARY)
	_try_send_next()
	_persist_queue()

func _enqueue_event(event_type: String, payload: Dictionary) -> void:
	if not enabled:
		return
	if endpoint_url.strip_edges().is_empty():
		return

	var envelope: Dictionary = {
		"event_type": event_type,
		"game_name": _get_game_name(),
		"build_version": _get_build_version(),
		"session_id": _session_id,
		"sent_at_unix": _now_unix(),
		"payload": payload,
	}
	if shared_secret.strip_edges() != "":
		envelope["secret"] = shared_secret

	_pending_events.append(envelope)
	_persist_queue()
	_try_send_next()

func _try_send_next() -> void:
	if _request_in_flight:
		return
	if not enabled:
		return
	if endpoint_url.strip_edges().is_empty():
		return
	if _pending_events.is_empty():
		return

	var envelope_json: String = JSON.stringify(_pending_events[0])
	var body: String = "payload=%s" % envelope_json.uri_encode()
	_log_payload("sending analytics payload", envelope_json)
	if _should_use_query_transport():
		var request_url: String = _build_query_request_url(envelope_json)
		if _try_send_with_web_query_ping(request_url):
			_pending_events.remove_at(0)
			_persist_queue()
			call_deferred("_try_send_next")
			return
		if not is_instance_valid(http_request):
			return
		_request_in_flight = true
		http_request.timeout = request_timeout_seconds
		var get_request_error: Error = http_request.request(
			request_url,
			PackedStringArray(),
			HTTPClient.METHOD_GET
		)
		if get_request_error != OK:
			_request_in_flight = false
			_schedule_retry()
			_log("request start failed: %s" % str(get_request_error))
		return

	if _try_send_with_beacon(body):
		_pending_events.remove_at(0)
		_persist_queue()
		call_deferred("_try_send_next")
		return

	if not is_instance_valid(http_request):
		return

	_request_in_flight = true
	http_request.timeout = request_timeout_seconds
	var request_error: Error = http_request.request(
		endpoint_url,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded;charset=UTF-8"]),
		HTTPClient.METHOD_POST,
		body
	)
	if request_error != OK:
		_request_in_flight = false
		_schedule_retry()
		_log("request start failed: %s" % str(request_error))

func _try_send_with_beacon(body: String) -> bool:
	if not OS.has_feature("web"):
		return false

	var endpoint_literal: String = JSON.stringify(endpoint_url)
	var body_literal: String = JSON.stringify(body)
	var js: String = """
(() => {
	if (typeof navigator === "undefined" || !navigator.sendBeacon) {
		return false;
	}
	const payload = %s;
	const blob = new Blob([payload], {type: "application/x-www-form-urlencoded;charset=UTF-8"});
	return navigator.sendBeacon(%s, blob);
})()
""" % [body_literal, endpoint_literal]

	var result: Variant = JavaScriptBridge.eval(js, true)
	if result is bool and result:
		_log("queued analytics payload via sendBeacon")
		return true
	return false

func _try_send_with_web_query_ping(request_url: String) -> bool:
	if not OS.has_feature("web"):
		return false

	var url_literal: String = JSON.stringify(request_url)
	var js: String = """
(() => {
	try {
		const img = new Image();
		img.src = %s;
		return true;
	} catch (_error) {
		return false;
	}
})()
""" % url_literal

	var result: Variant = JavaScriptBridge.eval(js, true)
	if result is bool and result:
		_log("queued analytics payload via image ping")
		return true
	return false

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_request_in_flight = false
	var response_text: String = _body.get_string_from_utf8()
	_log("request completed: result=%s response_code=%s body=%s" % [str(result), str(response_code), response_text])

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_log("request failed: result=%s response_code=%s" % [str(result), str(response_code)])
		_schedule_retry()
		return

	if not _response_reports_success(response_text):
		_log("analytics endpoint reported failure")
		_schedule_retry()
		return

	if not _pending_events.is_empty():
		_pending_events.remove_at(0)
		_persist_queue()
	_try_send_next()

func _response_reports_success(response_text: String) -> bool:
	if response_text.strip_edges().is_empty():
		return true

	var json := JSON.new()
	if json.parse(response_text) != OK:
		return false
	if not (json.data is Dictionary):
		return false

	var response_data: Dictionary = json.data
	return bool(response_data.get("ok", false))

func _schedule_retry() -> void:
	if is_instance_valid(retry_timer):
		retry_timer.start()
	_log("queued analytics retry in %s seconds" % str(RETRY_DELAY_SECONDS))
	_persist_queue()

func _load_queue() -> void:
	_pending_events.clear()
	if not FileAccess.file_exists(queue_save_path):
		return

	var file: FileAccess = FileAccess.open(queue_save_path, FileAccess.READ)
	if file == null:
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	if not (json.data is Array):
		return

	for event: Variant in json.data:
		if event is Dictionary:
			_pending_events.append(event)
	_log("loaded %s queued analytics events" % str(_pending_events.size()))

func _persist_queue() -> void:
	var file: FileAccess = FileAccess.open(queue_save_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_pending_events))

func _disconnect_runtime_hooks() -> void:
	if is_instance_valid(_tracked_player) and _tracked_player.tower_placed.is_connected(_on_tower_placed):
		_tracked_player.tower_placed.disconnect(_on_tower_placed)
	if is_instance_valid(_tracked_phases) and _tracked_phases.wave_cycle_started.is_connected(_on_wave_cycle_started):
		_tracked_phases.wave_cycle_started.disconnect(_on_wave_cycle_started)
	_tracked_player = null
	_tracked_phases = null

func _make_run_record(is_loading_save: bool) -> RunRecord:
	var record := RunRecord.new()
	record.run_id = _make_ephemeral_id("run")
	record.started_from_save = is_loading_save
	record.segment_started_ticks_msec = Time.get_ticks_msec()
	record.accumulated_run_seconds = 0.0
	record.max_wave_reached = 0
	record.finalized = false
	record.live = true
	return record

func _has_unfinalized_run() -> bool:
	return is_instance_valid(_current_run) and not _current_run.finalized

func _get_current_run_duration_seconds() -> float:
	if not is_instance_valid(_current_run):
		return 0.0

	if not _current_run.live:
		return _current_run.accumulated_run_seconds

	var elapsed_msec: int = maxi(Time.get_ticks_msec() - _current_run.segment_started_ticks_msec, 0)
	return _current_run.accumulated_run_seconds + (float(elapsed_msec) / 1000.0)

func _get_session_duration_seconds() -> int:
	var elapsed_msec: int = maxi(Time.get_ticks_msec() - _session_started_ticks_msec, 0)
	return int(floor(float(elapsed_msec) / 1000.0))

func _make_ephemeral_id(prefix: String) -> String:
	return "%s_%s_%s" % [prefix, str(_now_unix()), str(randi())]

func _should_use_query_transport() -> bool:
	return endpoint_url.find(GOOGLE_SCRIPT_ENDPOINT_HINT) != -1

func _build_query_request_url(envelope_json: String) -> String:
	var separator: String = "&" if endpoint_url.contains("?") else "?"
	return "%s%spayload=%s" % [endpoint_url, separator, envelope_json.uri_encode()]

func _increment_count(target: Dictionary[String, int], key: String, amount: int = 1) -> void:
	target[key] = target.get(key, 0) + amount

func _copy_int_dictionary(source: Dictionary[String, int]) -> Dictionary[String, int]:
	var output: Dictionary[String, int] = {}
	for key: String in source:
		output[key] = source[key]
	return output

func _load_int_dictionary(source: Dictionary) -> Dictionary[String, int]:
	var output: Dictionary[String, int] = {}
	for key: Variant in source:
		output[str(key)] = int(source[key])
	return output

func _tower_key_from_type(tower_type: Towers.Type) -> String:
	return Towers.Type.keys()[tower_type].to_lower()

func _relic_key_from_data(relic: RelicData) -> String:
	return RelicData.Type.keys()[relic.type].to_lower()

func _difficulty_key(game_difficulty: Run.GameDifficulty) -> String:
	return Run.GameDifficulty.keys()[game_difficulty].to_lower()

func _environment_key(game_environment: Run.GameEnvironment) -> String:
	return Run.GameEnvironment.keys()[game_environment].to_lower()

func _get_game_name() -> String:
	if game_name_override.strip_edges() != "":
		return game_name_override.strip_edges()
	return str(ProjectSettings.get_setting("application/config/name", "tower_defense"))

func _get_build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "unversioned"))

func _now_unix() -> int:
	return int(Time.get_unix_time_from_system())

func _log(message: String) -> void:
	if verbose_logging:
		print("Analytics: %s" % message)

func _log_payload(prefix: String, body: String) -> void:
	if not verbose_logging:
		return
	print("Analytics: %s" % prefix)
	print(body)
