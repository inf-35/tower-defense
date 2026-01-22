extends Node #(Units)
#repository of units, and their associated info
enum Type {
	BASIC,
	BUFF,
	DRIFTER,
	ARCHER,
	TROLL,
	WARRIOR,
	HEALER,
	SPRINTER,
	PROTECTOR,
	FLESHBLOB,
	FLESHLET,
	PHANTOM,
	EFFIGY,
	SUMMONER,
	ZOMBIE,
	GIANT
}

var unit_stats: Dictionary[Type, UnitData] = {}
var unit_prototypes: Dictionary[Type, Unit] = {}

var _units_modified_by_difficulty: Dictionary[Type, bool] = {} #whether a unit type's stats has been modified by difficulty

func start():
	unit_stats.clear()
	unit_prototypes.clear()
	#dont clear units modified by difficulty, as unitdatas are persistent
	_load_all_unit_stats()
	
func get_unit_prototype(unit_type: Type) -> Unit:
	if not unit_prototypes.has(unit_type): #if no prototype
		unit_prototypes[unit_type] = create_unit(unit_type) #create prototypical unit
		unit_prototypes[unit_type].abstractive = true #disable all effects and events
		unit_prototypes[unit_type].visible = false
		add_child(unit_prototypes[unit_type]) #trigger _ready() calls

		unit_prototypes[unit_type].position = Vector2(-2047 * unit_type * unit_prototypes[unit_type].unit_id, -4210 * unit_type * unit_prototypes[unit_type].unit_id) #somewhere extremely far away
		
		#these prototype units provide a "default" baseline to lookup from.
	return unit_prototypes[unit_type]
	
func get_unit_name(unit: Type) -> String:
	return unit_stats[unit].title
	
func get_unit_description(unit: Type) -> String:
	return unit_stats[unit].description
	
func get_stat_displays(unit: Type) -> Array[StatDisplayInfo]:
	return unit_stats[unit].stat_displays

func get_unit_flux(unit: Type) -> float:
	return unit_stats[unit].flux_value * 1.5

func get_unit_scene(unit: Type) -> PackedScene:
	return unit_stats[unit].unit_scene

func create_unit(unit_type: Type) -> Unit:
	var _unit: Unit = get_unit_scene(unit_type).instantiate()
	_unit.flux_value = get_unit_flux(unit_type)
	
	if Phases.current_game_difficulty == Phases.GameDifficulty.NORMAL and not _units_modified_by_difficulty.has(unit_type):
		if _unit.health_component: _unit.health_component.health_data.max_health = round(_unit.health_component.health_data.max_health * 0.8)
		if _unit.movement_component: _unit.movement_component.movement_data.max_speed *= 0.8
		if _unit.attack_component: _unit.attack_component.attack_data.cooldown *= 1.1
		_units_modified_by_difficulty[unit_type] = true
	return _unit
	
func _load_all_unit_stats():
	var base_directory: String = "res://Units/Enemies"
	
	var dir: DirAccess = DirAccess.open(base_directory)
	if not dir:
		push_error("Units: Failed to open base directory: " + base_directory)
		return

	print("Units: Starting load from " + base_directory)
	dir.list_dir_begin()
	var folder_name: String = dir.get_next()
	
	while folder_name != "":
		# check for directories (ignoring . and ..)
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var sub_dir_path: String = base_directory + "/" + folder_name + "/"
			
			# construct expected resource path: e.g. res://Units/Enemies/archer/archer.tres
			# note: relies on folder name matching file name exactly
			var resource_path: String = sub_dir_path + folder_name + ".tres"
			
			# handle (web)export remapping (.remap extension)
			# check if the file exists directly or with the .remap suffix
			if FileAccess.file_exists(resource_path) or FileAccess.file_exists(resource_path + ".remap"):
				var data_resource = load(resource_path)
				
				if data_resource is UnitData:
					# map folder name to enum key (e.g. "archer" -> ARCHER)
					var type_name: String = folder_name.to_upper()
					
					if Type.has(type_name):
						var type_enum: Type = Type[type_name]
						unit_stats[type_enum] = data_resource
						print("Units: Loaded " + type_name)
					else:
						push_warning("Units: Folder '" + folder_name + "' does not match any 'Units.Type' Enum.")
				else:
					push_error("Units: Failed to load valid UnitData at " + resource_path)
			else:
				push_warning("Units: No .tres found in " + sub_dir_path)
				pass

		folder_name = dir.get_next()
		
	dir.list_dir_end()
	print("Units: Load complete. Total units: ", unit_stats.size())
	
