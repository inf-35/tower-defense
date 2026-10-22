class_name Relics
#NOTE: this phrasing "static var" instead of "const ... preload()" is needed due to strange parser error bugs
const RELIC_DIRECTORY: String = "res://Content/Relics"

static var MONEY_MARKET: RelicData = load("res://Content/Relics/money_market/money_market.tres")
static var SUBPRIME: RelicData = load("res://Content/Relics/subprime/subprime.tres")
static var STUMBLING_BLOCKS: RelicData = load("res://Content/Relics/stumbling_blocks/stumbling_blocks.tres")
static var COMMON_COLD: RelicData = load("res://Content/Relics/common_cold/common_cold.tres")
static var CONTAGION: RelicData = load("res://Content/Relics/contagion/contagion.tres")
static var WILDERNESS: RelicData = load("res://Content/Relics/wilderness/wilderness.tres")
static var TRANCE: RelicData = load("res://Content/Relics/trance/trance.tres")
static var ENFILADE: RelicData = load("res://Content/Relics/enfilade/enfilade.tres")
static var AMBUSH: RelicData = load("res://Content/Relics/ambush/ambush.tres")
static var INFERNO: RelicData = load("res://Content/Relics/inferno/inferno.tres")
static var DYNAMITE: RelicData = load("res://Content/Relics/dynamite/dynamite.tres")
static var MUCOUS_SAC: RelicData = load("res://Content/Relics/mucous_sac/mucous_sac.tres")
static var AMETHYST_SKULL: RelicData = load("res://Content/Relics/amethyst_skull/amethyst_skull.tres")
static var ICE_SHARDS: RelicData = load("res://Content/Relics/ice_shards/ice_shards.tres")
static var WHITE_HOT_IRON: RelicData = load("res://Content/Relics/white_hot_iron/white_hot_iron.tres")
static var EARLY_BIRD: RelicData = load("res://Content/Relics/early_bird/early_bird.tres")
static var MACUAHUITL: RelicData = load("res://Content/Relics/macuahuitl/macuahuitl.tres")
static var MOKA_POT: RelicData = load("res://Content/Relics/moka_pot/moka_pot.tres")
static var PAPER_UMBRELLA: RelicData = load("res://Content/Relics/paper_umbrella/paper_umbrella.tres")
static var PAWN_STRUCTURE: RelicData = load("res://Content/Relics/pawn_structure/pawn_structure.tres")
static var SIGNAL_FLAG: RelicData = load("res://Content/Relics/signal_flag/signal_flag.tres")
static var MAGIC_BEANS: RelicData = load("res://Content/Relics/magic_beans/magic_beans.tres")
static var STRAW_HAT: RelicData = load("res://Content/Relics/straw_hat/straw_hat.tres")
static var WALLFLOWER: RelicData = load("res://Content/Relics/wallflower/wallflower.tres")
static var SIMPLE_BLADE: RelicData = load("res://Content/Relics/simple_blade/simple_blade.tres")
static var SPINNING_TOP: RelicData = load("res://Content/Relics/spinning_top/spinning_top.tres")
static var ALCHEMISTS_STONE: RelicData = load("res://Content/Relics/alchemists_stone/alchemists_stone.tres")
static var WEREGILD: RelicData = load("res://Content/Relics/weregild/weregild.tres")
static var EPIDEMIC: RelicData = load("res://Content/Relics/epidemic/epidemic.tres")
static var RUPTURED_HEART: RelicData = load("res://Content/Relics/ruptured_heart/ruptured_heart.tres")
static var BLACK_LILY: RelicData = load("res://Content/Relics/black_lily/black_lily.tres")
static var SCOUTING_GOGGLES: RelicData = load("res://Content/Relics/scouting_goggles/scouting_goggles.tres")
static var PALANTIR: RelicData = load("res://Content/Relics/palantir/palantir.tres")
static var KINGSGUARD: RelicData = load("res://Content/Relics/kingsguard/kingsguard.tres")
static var BOOKENDS: RelicData = load("res://Content/Relics/bookends/bookends.tres")
static var ERGOT: RelicData = load("res://Content/Relics/ergot/ergot.tres")
static var HEARTH: RelicData = load("res://Content/Relics/hearth/hearth.tres")
static var BASTION: RelicData = load("res://Content/Relics/bastion/bastion.tres")
static var EDELWEISS: RelicData = load("res://Content/Relics/edelweiss/edelweiss.tres")
static var SPRINKLERHEAD: RelicData = load("res://Content/Relics/sprinklerhead/sprinklerhead.tres")
static var SPARE_SUPPLIES: RelicData = load("res://Content/Relics/spare_supplies/spare_supplies.tres")

static var relics: Dictionary[RelicData.Type, RelicData] = {}
static var _is_loaded: bool = false

static func ensure_loaded() -> void: ##loads each canonical relic resource once, independently of reward prototypes
	if _is_loaded:
		return

	var dir: DirAccess = DirAccess.open(RELIC_DIRECTORY)
	if not dir:
		push_error("Relics: Failed to open directory: " + RELIC_DIRECTORY)
		return
	#collect all folders first
	var folder_names: Array[String] = []
	dir.list_dir_begin()
	var iterative_folder_name: String = dir.get_next()
	while iterative_folder_name != "":
		if dir.current_is_dir() and not iterative_folder_name.begins_with("."):
			folder_names.append(iterative_folder_name)
		iterative_folder_name = dir.get_next()
	dir.list_dir_end()
	folder_names.sort()
	#go through them and register the relics
	var paths_by_type: Dictionary[RelicData.Type, String] = {}
	for folder_name: String in folder_names:
		var resource_path: String = RELIC_DIRECTORY + "/" + folder_name + "/" + folder_name + ".tres"
		if not FileAccess.file_exists(resource_path) and not FileAccess.file_exists(resource_path + ".remap"):
			push_warning("Relics: No canonical .tres found in " + RELIC_DIRECTORY + "/" + folder_name)
			continue

		var resource: Resource = load(resource_path)
		if not resource is RelicData:
			push_error("Relics: Failed to load valid RelicData at " + resource_path)
			continue

		var relic: RelicData = resource as RelicData
		if not RelicData.Type.values().has(relic.type):
			push_error("Relics: Invalid type ID " + str(relic.type) + " at " + resource_path)
			continue

		if relics.has(relic.type):
			var existing_path: String = paths_by_type.get(relic.type, "an existing registry entry")
			push_error("Relics: Duplicate type ID " + str(relic.type) + " at " + resource_path + " (already registered from " + existing_path + ")")
			continue

		relics[relic.type] = relic
		paths_by_type[relic.type] = resource_path

	_is_loaded = true
	print("Relics: Loaded ", relics.size(), " definitions.")
