extends Node

const SAVE_PATH: String = "user://savegame.json"
const PROFILE_PATH: String = "user://profile.json"

#public api
func save_game() -> void:
	print("SaveLoad: Starting Save Process...")
	save_profile()

	var save_dict: Dictionary = {}

	save_dict["run"] = Run.get_save_data()

	#player context
	save_dict["player"] = Run.player.get_save_data()
	save_dict["phases"] = Run.phases.get_save_data()

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
	load_profile()

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

	if save_dict.has("player"):
		Run.player.load_save_data(save_dict["player"])

	#restore island
	if save_dict.has("island") and is_instance_valid(Run.references.island):
		#triggers reconstruction (terrain -> towers)
		Run.references.island.load_save_data(save_dict["island"])
	else:
		push_error("SaveLoad: Missing 'island' data in save file or Island reference missing.")
		return false

	print("SaveLoad: Load Complete.")
	return true

func save_profile() -> void:
	print("SaveLoad: Saving profile...")

	var profile_dict: Dictionary = {
		"settings": {
			"show_all_health_bars": Pause.show_all_health_bars,
		}
	}
	if is_instance_valid(Run.player):
		profile_dict["player"] = Run.player.get_profile()
	var json_string = JSON.stringify(profile_dict)

	#write to file
	var file = FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		print("SaveLoad: Game saved successfully to " + PROFILE_PATH)

func load_profile() -> bool:
	print("SaveLoad: Starting Load profile Process...")
	if not FileAccess.file_exists(PROFILE_PATH):
		print("SaveLoad: No save file found.")
		return false

	#read file
	var file = FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if not file:
		push_error("SaveLoad: Failed to open profile file.")
		return false

	var json_string = file.get_as_text()

	#parse json
	var json = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("SaveLoad: JSON Parse Error: " + json.get_error_message())
		return false

	var save_dict: Dictionary = json.data

	if save_dict.has("settings"):
		var settings_data: Dictionary = save_dict["settings"]
		Pause.show_all_health_bars = bool(settings_data.get("show_all_health_bars", false))

	if save_dict.has("player") and is_instance_valid(Run.player):
		Run.player.load_profile(save_dict["player"])
	return true

func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func has_profile() -> bool:
	return FileAccess.file_exists(PROFILE_PATH)

func delete_profile() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
