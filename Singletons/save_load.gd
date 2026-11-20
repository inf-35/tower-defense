extends Node

const SAVE_PATH: String = "user://savegame.json"
const PROFILE_PATH: String = "user://profile.json"
const BossEncounters := preload("res://Indexes/boss_encounters.gd")

var profile: PlayerProfile:
	get:
		return _profile

var _profile := PlayerProfile.new()
var _profile_loaded: bool = false
var _profile_can_save: bool = false
var _profile_dirty: bool = false

func _ready() -> void: ##loads app-owned progress before the main menu or a run reads it
	_profile.changed.connect(_on_profile_changed)
	load_profile()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_profile()

#public api
func save_game() -> void:
	print("SaveLoad: Starting Save Process...")
	save_profile()

	var save_dict: Dictionary = {}

	save_dict["run"] = Run.get_save_data()
	save_dict["analytics"] = Analytics.get_save_data()

	#player context
	save_dict["player"] = Run.player.get_save_data()
	save_dict["phases"] = Run.phases.get_save_data()
	save_dict["boss_encounters"] = Run.boss_encounters.get_save_data() if is_instance_valid(Run.boss_encounters) else {}

	#island context
	if is_instance_valid(Run.references.island):
		save_dict["island"] = Run.references.island.get_save_data()
	else:
		push_error("SaveLoad: Island reference missing. Cannot save world.")
		return

	#serialise to string
	var json_string = JSON.stringify(save_dict)

	#write to file
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		print("SaveLoad: Game saved successfully to " + SAVE_PATH)
	else:
		push_error("SaveLoad: Failed to open file for writing: " + SAVE_PATH)

func load_game() -> bool:
	print("SaveLoad: Starting Load Process...")

	if not FileAccess.file_exists(SAVE_PATH):
		print("SaveLoad: No save file found.")
		return false

	#read file
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("SaveLoad: Failed to open save file.")
		return false

	var json_string = file.get_as_text()

	#parse json
	var json = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("SaveLoad: JSON Parse Error: " + json.get_error_message())
		return false

	var save_dict: Dictionary = json.data

	if save_dict.has("run"):
		Run.load_save_data(save_dict["run"])

	#restore phases
	if save_dict.has("phases"):
		Run.phases.load_save_data(save_dict["phases"])
	else:
		push_error("SaveLoad: Missing 'phases' data.")

	#restore island
	if save_dict.has("island") and is_instance_valid(Run.references.island):
		#triggers reconstruction (terrain -> towers)
		Run.references.island.load_save_data(save_dict["island"])
	else:
		push_error("SaveLoad: Missing 'island' data in save file or Island reference missing.")
		return false

	if save_dict.has("player"):
		Run.player.load_save_data(save_dict["player"])
	if save_dict.has("analytics"):
		Analytics.load_save_data(save_dict["analytics"])
	if save_dict.has("boss_encounters") and is_instance_valid(Run.boss_encounters):
		var boss_data: Dictionary = save_dict["boss_encounters"]
		Run.boss_encounters.load_save_data(boss_data if _should_restore_boss_encounter(boss_data) else {})

	print("SaveLoad: Load Complete.")
	return true

func save_profile() -> void: ##captures live preferences and retries any pending profile write
	var settings: Dictionary[String, Variant] = _profile.get_settings()
	settings.merge(WindowSettings.get_profile_data(), true)
	settings["show_all_health_bars"] = Pause.show_all_health_bars
	settings["show_attached_effect_icons"] = Pause.show_attached_effect_icons
	_profile.set_settings(settings)
	_flush_profile()

func load_profile() -> bool: ##hydrates the shared object once; repeated calls preserve current in-memory progress
	if _profile_loaded:
		return _profile_can_save
	_profile_loaded = true
	var profile_data: Variant = _read_profile()
	_profile_can_save = profile_data is Dictionary and _profile.load_profile(profile_data)
	if _profile_can_save:
		_profile_dirty = not profile_data.is_empty() and int(profile_data.get("version", 0)) < PlayerProfile.SCHEMA_VERSION
	var settings: Dictionary[String, Variant] = _profile.get_settings()
	Pause.show_all_health_bars = bool(settings.get("show_all_health_bars", false))
	Pause.show_attached_effect_icons = bool(settings.get("show_attached_effect_icons", true))
	WindowSettings.apply_startup_settings(settings)
	return _profile_can_save

func get_wave_records() -> Dictionary[String, Dictionary]: ##reads a snapshot from memory for the index
	return _profile.get_wave_records()

func record_wave_clear(environment: Run.GameEnvironment, difficulty: Run.GameDifficulty, wave_number: int) -> void: ##converts run enums to persisted keys and records the clear in memory
	var environment_key: String = Run.GameEnvironment.keys()[environment].to_lower()
	var difficulty_key: String = Run.GameDifficulty.keys()[difficulty].to_lower()
	_profile.record_wave_clear(environment_key, difficulty_key, wave_number)

func _on_profile_changed() -> void: ##persists infrequent settings, tutorial, and record changes immediately
	_profile_dirty = true
	_flush_profile()

func _flush_profile() -> void: ##keeps failed writes pending and preserves an unreadable on-disk profile
	if not _profile_dirty or not _profile_can_save:
		return
	if _write_profile(_profile.get_profile()):
		_profile_dirty = false

func _read_profile() -> Variant: ##returns a blank profile on first launch and null if an existing profile cannot be read safely
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var file: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveLoad: Failed to open profile file.")
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("SaveLoad: Invalid profile data. " + json.get_error_message())
		return null
	return json.data

func _write_profile(profile_dict: Dictionary) -> bool: ##writes the cached snapshot without consulting run-owned state
	var file: FileAccess = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file == null or not file.store_string(JSON.stringify(profile_dict)):
		push_error("SaveLoad: Failed to write profile file.")
		return false
	return true

func _should_restore_boss_encounter(data: Dictionary) -> bool: ##keeps stale boss-test saves from restoring encounters no longer scheduled by phases
	if data.is_empty() or not bool(data.get("active", false)):
		return true
	if not is_instance_valid(Run.phases):
		return false

	var boss_wave: int = int(data.get("wave_number", 0))
	var saved_type: BossEncounters.Type = int(data.get("encounter_type", BossEncounters.Type.NONE))
	if boss_wave <= 0 or saved_type == BossEncounters.Type.NONE:
		return false
	return Run.phases.get_boss_encounter_type(boss_wave) == saved_type

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func has_profile() -> bool:
	return FileAccess.file_exists(PROFILE_PATH)

func delete_profile() -> void: ##clears the same cached object only after its stored profile has been removed
	if FileAccess.file_exists(PROFILE_PATH) and DirAccess.remove_absolute(PROFILE_PATH) != OK:
		push_error("SaveLoad: Failed to delete profile file.")
		return
	_profile.load_profile({})
	_profile_dirty = false
	_profile_can_save = true
