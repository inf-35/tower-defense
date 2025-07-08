extends Node #Towers
#repository of towers, and their associated info

class TowerStat: #data container for stats
	var element: Element
	var construct: int = 0 #minimum terrain level to construct
	var tower_scene: PackedScene
	var flux_cost: float = 0.0
	
	var tower_name: String #TODO: replace with localisable variables
	var tower_description: String
	
	func _init(_tower_scene: PackedScene, _element: Element, _construct: int = 0, _flux_cost: float = 0.0, _tower_name : String = "", _tower_description : String = ""):
		tower_scene = _tower_scene
		element = _element
		construct = _construct
		flux_cost = _flux_cost
		tower_name = _tower_name
		tower_description = _tower_description

enum Type {
	VOID, #custom type for tower destruction
	PLAYER_CORE,
	TURRET,
	FROST_TOWER,
	CANNON,
	BLUEPRINT_HARVESTER,
	PALISADE,
	CATALYST,
	FLAMETHROWER
}

enum Element {
	KINETIC,
	FROST,
	FIRE,
	NATURE,
	SPARK,
	ARCANE,
	NEUTRAL,
}

static var tower_stats: Dictionary[Type, TowerData] = {} #populated at startup

var tower_prototypes: Dictionary[Type, Tower] = {} #prototypical towers created and stored as reference

func get_tower_stat(tower_type: Type, attr: Attributes.id): #gets a tower's stat based off an unmodified prototype
	if not tower_prototypes.has(tower_type): #if no prototype
		tower_prototypes[tower_type] = create_tower(tower_type) #create prototypical tower
	
	var prototype: Tower = tower_prototypes[tower_type]

	var value = prototype.get_stat(attr)
	if not value: #i.e. null
		return 0.0
	return prototype.get_stat(attr)

func get_tower_prototype(tower_type: Type) -> Tower:
	if not tower_prototypes.has(tower_type): #if no prototype
		tower_prototypes[tower_type] = create_tower(tower_type) #create prototypical tower
	
	return tower_prototypes[tower_type]

static func get_tower_element(tower_type: Type) -> Towers.Element:
	return tower_stats[tower_type].element

static func get_tower_cost(tower_type: Type) -> float:
	return tower_stats[tower_type].cost

static func get_tower_minimum_terrain(tower_type: Type) -> Terrain.Level:
	return tower_stats[tower_type].minimum_terrain

static func get_tower_scene(tower_type: Type) -> PackedScene:
	return tower_stats[tower_type].tower_scene

static func get_tower_name(tower_type: Type) -> String:
	return tower_stats[tower_type].tower_name

static func get_tower_description(tower_type: Type) -> String:
	return tower_stats[tower_type].tower_description

static func create_tower(tower_type: Type) -> Tower:
	return get_tower_scene(tower_type).instantiate()

static func _load_all_tower_stats() -> void:
	var base_directory = "res://Units/Towers/"
	
	var dir: DirAccess = DirAccess.open(base_directory)
	if not dir:
		push_error("Failed to open base tower directory: " + base_directory)
		return

	dir.list_dir_begin()
	var folder_name = dir.get_next()
	while folder_name != "":
		# Check if the current item is a directory and not "." or ".."
		if dir.current_is_dir() and not folder_name.begins_with("."):
			
			# Construct the expected path to the .tres file based on the new structure
			var resource_path: String = base_directory + folder_name + "/" + folder_name + ".tres"
			#expectedstructure res://Units/Towers/[tower type]/[tower type].tres
			# Before trying to load, check if the file actually exists.
			if FileAccess.file_exists(resource_path):
				var stat_resource: TowerData = load(resource_path)
				
				if stat_resource:
					# The enum key is derived from the folder name, e.g., "frost_tower" -> "FROST_TOWER"
					var type_name: String = folder_name.to_upper()
					print(type_name)
					# Convert the string name to the actual enum value
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
