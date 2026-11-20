extends RefCounted
class_name PlayerProfile

signal changed

const SCHEMA_VERSION: int = 1

enum TutorialFlag {
	TROLL = 2,
	TOWER_DESTROYED = 3,
	RUINS = 4,
	RITE = 5,
	ONBOARDING = 6,
	SHOP = 7,
}

var _settings: Dictionary[String, Variant] = {}
var _completed_tutorials: Dictionary[String, bool] = {}
var _best_waves: Dictionary[String, Dictionary] = {}

func get_settings() -> Dictionary[String, Variant]: ##returns a snapshot so callers cannot bypass change tracking
	return _settings.duplicate(true)

func set_settings(settings: Dictionary) -> void: ##replaces persisted preferences and reports actual changes
	if _settings == settings:
		return
	_settings.clear()
	_settings.assign(settings.duplicate(true))
	changed.emit()

func has_completed_tutorial(flag: TutorialFlag) -> bool: ##reads completion independently of the current run
	var key: String = TutorialFlag.find_key(flag).to_lower()
	return _completed_tutorials.get(key, false)

func complete_tutorial(flag: TutorialFlag) -> void: ##records each tutorial completion once
	if has_completed_tutorial(flag):
		return
	var key: String = TutorialFlag.find_key(flag).to_lower()
	_completed_tutorials[key] = true
	changed.emit()

func get_wave_records() -> Dictionary[String, Dictionary]: ##returns a snapshot of best clears by environment and difficulty
	return _best_waves.duplicate(true)

func get_best_wave_clear() -> int: ##returns the highest fully cleared wave across every recorded run configuration
	var best_wave: int = 0
	for records: Dictionary in _best_waves.values():
		for value: Variant in records.values():
			best_wave = maxi(best_wave, int(value))
	return best_wave

func record_wave_clear(environment_key: String, difficulty_key: String, wave_number: int) -> void: ##raises one setup's record without retaining runtime objects
	var records: Dictionary = _best_waves.get(environment_key, {})
	if wave_number <= int(records.get(difficulty_key, 0)):
		return
	records[difficulty_key] = wave_number
	_best_waves[environment_key] = records
	changed.emit()

func get_profile() -> Dictionary[String, Variant]: ##serializes the complete profile without exposing its mutable containers
	return {
		"version": SCHEMA_VERSION,
		"settings": _settings.duplicate(true),
		"completed_tutorials": _completed_tutorials.duplicate(),
		"best_waves": _best_waves.duplicate(true),
	}

func load_profile(data: Dictionary) -> bool: ##hydrates a profile silently and migrates the former player-owned tutorial flags
	if int(data.get("version", 0)) > SCHEMA_VERSION:
		push_error("PlayerProfile: This profile requires a newer game version.")
		return false
	var settings: Variant = data.get("settings", {})
	var tutorials: Variant = data.get("completed_tutorials", {})
	var best_waves: Variant = data.get("best_waves", {})
	var legacy_player: Variant = data.get("player", {})
	if not settings is Dictionary or not tutorials is Dictionary or not best_waves is Dictionary or not legacy_player is Dictionary:
		push_error("PlayerProfile: Invalid profile sections.")
		return false
	var legacy_tutorials: Variant = legacy_player.get("completed_tutorials", {})
	if not legacy_tutorials is Dictionary:
		push_error("PlayerProfile: Invalid legacy tutorial data.")
		return false
	for environment_key: String in best_waves:
		if not best_waves[environment_key] is Dictionary:
			push_error("PlayerProfile: Invalid wave records.")
			return false
		for value: Variant in best_waves[environment_key].values():
			if not (value is int or value is float):
				push_error("PlayerProfile: Invalid wave number.")
				return false

	_settings.clear()
	_settings.assign(settings.duplicate(true))
	_completed_tutorials.clear()
	for name: String in TutorialFlag:
		var key: String = name.to_lower()
		var legacy_key: String = str(TutorialFlag[name])
		if bool(tutorials.get(key, false)) or bool(legacy_tutorials.get(legacy_key, false)):
			_completed_tutorials[key] = true
	_best_waves.clear()
	for environment_key: String in best_waves:
		var records: Dictionary[String, int] = {}
		for difficulty_key: String in best_waves[environment_key]:
			records[difficulty_key] = maxi(int(best_waves[environment_key][difficulty_key]), 0)
		_best_waves[environment_key] = records
	return true
