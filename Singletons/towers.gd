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
	ARTIFACT,
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
	ARC_DAMAGE,
	RITE_BLOOD,
	RITE_CLUBS,
	RITE_RAMPAGE,
	RITE_OIL,
	RITE_WHEEL,
	RITE_DRUMS,
	HAMLET,
	FARM,
	BRICKLAYER,
	WATCHTOWER,
	RITE_HAMMER,
	RITE_SCYTHE,
	RITE_SNAIL,
	CAMPGROUNDS,
	OUTPOST,
	RITE_HASTE,
	RITE_SACRIFICE,
	SIPHON,
	RESONATOR,
	BLOOD_ALTAR,
	SOUL_LINK,
	RITE_BALANCE,
	RITE_OBSIDIAN,
	RITE_GLASS,
	RITE_SALT,
	RUINS,
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

const TOWER_COST_BASE_SCALING: float = 0.05 ##0.05 = +5% cost per existing tower, 0.0 disables scaling
const TOWER_COST_SCALING_MULTIPLIER: float = 0.0 ##0.0 -> no scaling, 1.0 -> normal scaling
const TOWER_COST_INCREMENT: float = 0.05  ##smallest increment to which tower price values will snap to

const VERBOSE: bool = false
const PROTOTYPE_LOAD_CHUNK: int = 4

func get_tower_stat(tower_type: Type, attr: Attributes.id) -> Variant: #gets a tower's stat based off an unmodified prototype
	var prototype: Tower = get_tower_prototype(tower_type)

	var value = prototype.get_stat(attr)
	if not value: #i.e. null
		return 0.0
	return prototype.get_stat(attr)

func get_tower_prototype(tower_type: Type) -> Tower:
	if not tower_prototypes.has(tower_type): #if no prototype
		tower_prototypes[tower_type] = create_tower(tower_type) #create prototypical tower
		tower_prototypes[tower_type].abstractive = true #disable all effects and events
		tower_prototypes[tower_type].visible = false
		add_child.call_deferred(tower_prototypes[tower_type]) #trigger _ready() calls

		tower_prototypes[tower_type].tower_position = Vector2i(1915 * tower_type * tower_prototypes[tower_type].unit_id, 5823 * tower_type * tower_prototypes[tower_type].unit_id) #somewhere extremely far away
		tower_prototypes[tower_type].facing = Tower.Facing.UP
		tower_prototypes[tower_type].size = Towers.get_tower_size(tower_type)
		#these prototype towers provide a "default" baseline to lookup from.
	return tower_prototypes[tower_type]

func reset_tower_prototype(tower_type: Type) -> void: ##resets a tower prototype (by type). use after manipulation of prototype
	var prototype: Tower = tower_prototypes[tower_type] as Tower
	if prototype: #1915 and 5823 are arbitrary, large, noncongruent values
		prototype.tower_position = Vector2i(1915 * tower_type * prototype.unit_id, 5823 * tower_type * prototype.unit_id)
		prototype.facing = Tower.Facing.UP

func get_tower_size(tower_type: Type) -> Vector2i:
	return tower_stats[tower_type].size

func get_tower_navcost(tower_type: Type) -> int:
	return tower_stats[tower_type].navcost

func get_tower_icon(tower_type: Type) -> Texture2D:
	return tower_stats[tower_type].icon

func get_tower_base_cost(tower_type: Type) -> float:
	return tower_stats[tower_type].cost

func get_tower_actions(tower_type: Type) -> Array[InspectorAction]:
	return tower_stats[tower_type].inspector_actions

func get_tower_element(tower_type: Type) -> Towers.Element:
	return tower_stats[tower_type].element

func get_cost_scaling(tower_type: Type) -> float:
	if tower_stats[tower_type].cost_scaling_override == INF:
		return TOWER_COST_BASE_SCALING
	else:
		return tower_stats[tower_type].cost_scaling_override

func get_tower_cost(tower_type: Type) -> float: ##returns the cost of the NEXT tower to be built
	if not tower_stats.has(tower_type):
		push_warning("Towers: tried to get tower cost of non-existing tower-type")
		return 0.0

	var base_cost: float = tower_stats[tower_type].cost
	if is_tower_rite(tower_type) or is_tower_environmental(tower_type):
		return base_cost

	var current_count: int = 0
	if is_instance_valid(Run.references.island):
		current_count = Run.references.island.get_towers_by_type(tower_type).size()

	var final_cost: float = base_cost * pow(1.0 + get_cost_scaling(tower_type) * TOWER_COST_SCALING_MULTIPLIER, current_count)

	return snappedf(final_cost, TOWER_COST_INCREMENT)

func get_tower_refund_value(tower_type: Type) -> float: ##returns the refund value for selling one tower of this type right now (cost of last tower built)
	if not tower_stats.has(tower_type):
		push_warning("Towers: tried to get refund value of non-existing tower-type@")
		return 0.0

	if is_tower_rite(tower_type) or is_tower_environmental(tower_type):
		return tower_stats[tower_type].cost

	var current_count: int = 0
	if is_instance_valid(Run.references.island):
		current_count = Run.references.island.get_towers_by_type(tower_type).size()

	if current_count == 0:
		return tower_stats[tower_type].cost ##nothing to sell; fallback to base cost

	var base_cost: float = tower_stats[tower_type].cost
	var refund_value: float = base_cost * pow(1.0 +  get_cost_scaling(tower_type) * TOWER_COST_SCALING_MULTIPLIER, current_count - 1)

	return snappedf(refund_value, TOWER_COST_INCREMENT)

func get_max_level(tower_type : Type) -> int:
	return tower_stats[tower_type].max_level #TODO: actually implement this

func get_tower_capacity(tower_type : Type) -> float:
	return tower_stats[tower_type].required_capacity

func get_tower_scene(tower_type: Type) -> PackedScene:
	return tower_stats[tower_type].tower_scene

func get_tower_allowed_terrains(tower_type: Type) -> Array[Terrain.Base]:
	return tower_stats[tower_type].allowed_terrain

func get_tower_name(tower_type: Type) -> String:
	return tower_stats[tower_type].tower_name

func get_rite_short_name(tower_type: Type) -> String:
	if not tower_stats.has(tower_type):
		return ""

	var authored_name: String = tower_stats[tower_type].rite_short_name.strip_edges()
	if not authored_name.is_empty():
		return authored_name.to_lower()

	var tower_name: String = get_tower_name(tower_type)
	if tower_name.begins_with("Rite of "):
		return tower_name.trim_prefix("Rite of ").to_lower()
	if tower_name.ends_with(" Rite"):
		return tower_name.trim_suffix(" Rite").to_lower()
	return tower_name.to_lower()

func get_buff_short_name(tower_type: Type) -> String:
	match tower_type:
		Type.CAMPGROUNDS:
			return "camp"
		Type.WATCHTOWER:
			return "watch"

	if is_tower_rite(tower_type):
		return get_rite_short_name(tower_type)

	if not tower_stats.has(tower_type):
		return ""
	return get_tower_name(tower_type).to_lower()

func get_tower_preview(tower_type: Type) -> Texture2D:
	return tower_stats[tower_type].preview

func get_tower_description(tower_type: Type) -> String:
	return tower_stats[tower_type].tower_description

func is_tower_rite(tower_type: Type) -> bool:
	if not tower_stats.has(tower_type):
		return false
	return tower_stats[tower_type].is_rite

func is_tower_buff_source(tower_type: Type) -> bool:
	return tower_type in [
		Type.AMPLIFIER,
		Type.CAMPGROUNDS,
		Type.OUTPOST,
		Type.SHIELD,
		Type.WATCHTOWER,
	] or is_tower_rite(tower_type)

func is_tower_upgrade(tower_type: Type) -> bool:
	if not tower_stats.has(tower_type):
		return false
	return tower_stats[tower_type].is_upgrade

func is_tower_environmental(tower_type: Type) -> bool:
	if not tower_stats.has(tower_type):
		return false
	return tower_stats[tower_type].is_environmental

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
	tower.set_meta(ID.UnitMeta.IS_IMPORTANT, true) #towers are always important
	return tower

func _load_all_tower_stats() -> void:
	var base_directory: String = "res://Units/Towers/"

	var dir: DirAccess = DirAccess.open(base_directory)
	if not dir:
		push_error("Failed to open base tower directory: " + base_directory)
		return

	dir.list_dir_begin()
	var folder_name: String = dir.get_next()
	#iterate through all folders in base_directory
	while folder_name != "":
		#check if the current item is a directory and not "." or ".."
		if dir.current_is_dir() and not folder_name.begins_with("."):
			#debug: list contents of this specific folder
			#var sub_dir_path: String = base_directory + folder_name + "/"
			#var sub_dir: DirAccess = DirAccess.open(sub_dir_path)

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

			#construct the expected path to the .tres file based on the new structure
			var resource_path: String = base_directory + folder_name + "/" + folder_name + ".tres"
			#format:  res://units/towers/[tower type]/[tower type].tres
			#before trying to load, check if the file actually exists.
			if FileAccess.file_exists(resource_path) or FileAccess.file_exists(resource_path + ".remap"): #remap is for web builds
				var stat_resource: TowerData = load(resource_path)

				if stat_resource:
					#the enum key is derived from the folder name, e.g., "frost_tower" -> "frost_tower"
					var type_name: String = folder_name.to_upper()
					#convert the string name to the actual enum value
					if Type.has(type_name):
						if VERBOSE: print("Assigned " + resource_path + " to " + type_name)
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

func _init() -> void:
	_load_all_tower_stats()

func start() -> void:
	for tower_type in tower_stats:
		get_tower_prototype(tower_type)

func start_async(progress_callback: Callable = Callable()) -> void:
	var tower_types: Array = tower_stats.keys()
	var total_types: int = maxi(tower_types.size(), 1)

	for i: int in range(tower_types.size()):
		get_tower_prototype(tower_types[i])
		if (i + 1) % PROTOTYPE_LOAD_CHUNK == 0 or i == tower_types.size() - 1:
			if progress_callback.is_valid():
				var t := float(i + 1) / float(total_types)
				progress_callback.call("Preparing towers...", lerpf(0.24, 0.58, t))
			await get_tree().process_frame
