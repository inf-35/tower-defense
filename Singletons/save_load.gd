extends Node

const SAVE_PATH: String = "user://savegame.json"
const PROFILE_PATH: String = "user://profile.json"

#public api
func save_game() -> void:
	print("SaveLoad: Starting Save Process...")
	save_profile()
	
	var save_dict: Dictionary = {}
	
	#player context
	save_dict["player"] = Player.get_save_data()
	save_dict["phases"] = Phases.get_save_data()
		
	#island context
	if is_instance_valid(References.island):
		save_dict["island"] = References.island.get_save_data()
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
	
	# parse JSON
	var json = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("SaveLoad: JSON Parse Error: " + json.get_error_message())
		return false
		
	var save_dict: Dictionary = json.data
	
	#restore phases
	if save_dict.has("phases"):
		Phases.load_save_data(save_dict["phases"])
	else:
		push_error("SaveLoad: Missing 'phases' data.")
		
	if save_dict.has("player"):
		Player.load_save_data(save_dict["player"])

	#restore island
	if save_dict.has("island") and is_instance_valid(References.island):
		#triggers reconstruction (terrain -> towers)
		References.island.load_save_data(save_dict["island"])
	else:
		push_error("SaveLoad: Missing 'island' data in save file or Island reference missing.")
		return false
		
	print("SaveLoad: Load Complete.")
	return true

func save_profile() -> void:
	print("SaveLoad: Saving profile...")
	
	var profile_dict: Dictionary = {}
	profile_dict["player"] = Player.get_profile()
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
	
	# parse JSON
	var json = JSON.new()
	var error: Error = json.parse(json_string)
	if error != OK:
		push_error("SaveLoad: JSON Parse Error: " + json.get_error_message())
		return false
		
	var save_dict: Dictionary = json.data
	
	if save_dict.has("player"):
		Player.load_profile(save_dict["player"])
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
