extends Node #Towers
#repository of towers, and their associated info

enum Type {
	VOID, ##custom type for tower destruction
	PLAYER_CORE,
	TURRET,
	FROST_TOWER,
	CANNON,
	GENERATOR,
	PALISADE,
	CATALYST, ##deprecated
	AMPLIFIER,
	BREACH,
	ANOMALY,
	MINIGUN,
	SHIELD,
	SNIPER,
	POISON,
	PLANT,
	ARC,
	PRISM,
	MAGE,
	FOREST,
	FLAMETHROWER,
	VENOM,
	MORTAR,
	FIREWALL,
	SNOWBALL,
	SUNBEAM,
	PALISADE_UPGRADE_1,
	PLANT_UPGRADE_1,
	RITE_CURSES,
	RITE_POISONS,
	RITE_FROST,
	RITE_FLAME,
	RITE_LIBERTY,
	RITE_FIST,
	TURRET_UPGRADE_BLEED,
	TURRET_UPGRADE_DAMAGE,
	CANNON_UPGRADE_GRAPESHOT,
	CANNON_UPGRADE_DAMAGE,
	SUNBEAM_TRIPLET,
	SUNBEAM_DAMAGE,
	FROST_ACUTE,
	FROST_DIFFUSE,
	POISON_ACUTE,
	POISON_CHRONIC,
	ARC_CHAIN,
	ARC_DAMAGE
}

enum Element {
	KINETIC,
	FROST,
	FIRE,
	NATURE,
	ARCANE,
	NEUTRAL,
}

var tower_stats: Dictionary[Type, TowerData] = {} #populated at startup

var tower_prototypes: Dictionary[Type, Tower] = {} #prototypical towers created and stored as reference

func get_tower_stat(tower_type: Type, attr: Attributes.id): #gets a tower's stat based off an unmodified prototype
	var prototype: Tower = get_tower_prototype(tower_type)

	var value = prototype.get_stat(attr)
	if not value: #i.e. null
		return 0.0
	return prototype.get_stat(attr)

func get_tower_prototype(tower_type: Type) -> Tower:
	if not tower_prototypes.has(tower_type): #if no prototype
		tower_prototypes[tower_type] = create_tower(tower_type) #create prototypical tower
		tower_prototypes[tower_type].abstractive = true #disable all effects and events
		add_child(tower_prototypes[tower_type]) #trigger _ready() calls

		tower_prototypes[tower_type].tower_position = Vector2i(1915 * tower_type * tower_prototypes[tower_type].unit_id, 5823 * tower_type * tower_prototypes[tower_type].unit_id) #somewhere extremely far away
		#these prototype towers provide a "default" baseline to lookup from.
	return tower_prototypes[tower_type]

func reset_tower_prototype(tower_type: Type) -> void: ##resets a tower prototype (by type). use after manipulation of prototype
	var prototype := tower_prototypes[tower_type] as Tower
	if prototype:
		prototype.tower_position = Vector2i(1915 * tower_type * prototype.unit_id, 5823 * tower_type * prototype.unit_id)
	
func get_tower_size(tower_type: Type) -> Vector2i:
	return tower_stats[tower_type].size
	
func get_tower_navcost(tower_type: Type) -> int:
	return tower_stats[tower_type].navcost

func get_tower_icon(tower_type: Type) -> Texture2D:
	return tower_stats[tower_type].icon
	
func get_tower_actions(tower_type: Type) -> Array[InspectorAction]:
	return tower_stats[tower_type].inspector_actions

func get_tower_element(tower_type: Type) -> Towers.Element:
	return tower_stats[tower_type].element

func get_tower_cost(tower_type: Type) -> float:
	return tower_stats[tower_type].cost

func get_max_level(tower_type : Type) -> int:
	return tower_stats[tower_type].max_level #TODO: actually implement this
	
func get_tower_capacity(tower_type : Type) -> float:
	return tower_stats[tower_type].required_capacity

func get_tower_scene(tower_type: Type) -> PackedScene:
	return tower_stats[tower_type].tower_scene

func get_tower_name(tower_type: Type) -> String:
	return tower_stats[tower_type].tower_name
	
func get_tower_preview(tower_type: Type) -> Texture2D:
	return tower_stats[tower_type].preview

func get_tower_description(tower_type: Type) -> String:
	return tower_stats[tower_type].tower_description

func is_tower_rite(tower_type: Type) -> bool:
	if not tower_stats.has(tower_type):
		return false
	return tower_stats[tower_type].is_rite

func is_tower_upgrade(tower_type: Type) -> bool:
	if not tower_stats.has(tower_type):
		return false
	return tower_stats[tower_type].is_upgrade
	
func get_tower_upgrades(tower_type: Type) -> Array[Towers.Type]:
	if not tower_stats.has(tower_type):
		return []
	return tower_stats[tower_type].upgrades_into.keys()

func get_tower_upgrade_cost(tower_type: Type, upgrade_type: Type) -> float: ##returns -1 for invalid upgrade
	if not tower_stats[tower_type].upgrades_into.has(upgrade_type):
		return -1
	return tower_stats[tower_type].upgrades_into[upgrade_type]

func create_tower(tower_type: Type) -> Tower:
	var tower: Tower = get_tower_scene(tower_type).instantiate()
	tower.type = tower_type
	tower.flux_value = get_tower_cost(tower_type)
	return tower

func _load_all_tower_stats() -> void:
	var base_directory: String = "res://Units/Towers/"
	
	var dir: DirAccess = DirAccess.open(base_directory)
	if not dir:
		push_error("Failed to open base tower directory: " + base_directory)
		return

	dir.list_dir_begin()
	var folder_name: String = dir.get_next()
	# iterate through all folders in base_directory
	while folder_name != "":
		# check if the current item is a directory and not "." or ".."
		if dir.current_is_dir() and not folder_name.begins_with("."):
			# DEBUG: list contents of this specific folder
			#var sub_dir_path: String = base_directory + folder_name + "/"
			#var sub_dir: DirAccess = DirAccess.open(sub_dir_path)
			#
			#if sub_dir:
				#push_warning("Scanning Folder: " + folder_name)
				#sub_dir.list_dir_begin()
				#var sub_file_name: String = sub_dir.get_next()
				#while sub_file_name != "":
					#push_warning("  Found File: " + sub_file_name)
					#sub_file_name = sub_dir.get_next()
				#sub_dir.list_dir_end()
			#else:
				#push_error("Could not access sub-directory: " + sub_dir_path)
				
			# construct the expected path to the .tres file based on the new structure
			var resource_path: String = base_directory + folder_name + "/" + folder_name + ".tres"
			# format:  res://Units/Towers/[tower type]/[tower type].tres
			# before trying to load, check if the file actually exists.
			if FileAccess.file_exists(resource_path) or FileAccess.file_exists(resource_path + ".remap"): #remap is for web builds
				var stat_resource: TowerData = load(resource_path)
				
				if stat_resource:
					# the enum key is derived from the folder name, e.g., "frost_tower" -> "FROST_TOWER"
					var type_name: String = folder_name.to_upper()
					# convert the string name to the actual enum value
					if Type.has(type_name):
						print("Assigned " + resource_path + " to " + type_name)
						var tower_type: Type = Type[type_name]
						tower_stats[tower_type] = stat_resource
					else:
						push_error("Enum 'Type' has no key for: " + type_name)
				else:
					push_error("Failed to load resource at: " + resource_path)
			else:
				push_error("Resource did not exist at: " + resource_path)

		folder_name = dir.get_next()
		
	dir.list_dir_end()

func _init():
	_load_all_tower_stats()
