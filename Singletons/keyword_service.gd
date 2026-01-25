extends Node

var ICON_SIZE: int = 40
#NOTE:
#parameters: icon_size, color, label
# master dictionary for static keywords
const KEYWORDS: Dictionary[String, Dictionary] = {
	"GOLD": {
		"title": "Gold",
		"display": "",
		"description": "The primary currency used for building and upgrading towers.",
		"icon": preload("res://Assets/gold_icon.png"),
	},
	"PLAYER_HP": {
		"title": "Player Health",
		"display": "",
		"description": "If this reaches 0, the run ends.",
		"icon": preload("res://Assets/hp_icon.png"),
	},
	"POPULATION" : {
		"title": "Population",
		"display": "",
		"description": "Towers require population to operate. Cap is increased by building {T_GENERATOR|label=Villages}.",
		"icon": preload("res://Assets/population_icon.png")
	},
	"UNIT_HP": {
		"title": "Unit health",
		"display": "",
		"description": "How much damage this unit can take before being destroyed.",
		"icon": preload("res://Assets/hp_icon.png")
	},
	"UNIT_DAMAGE": {
		"title": "Damage",
		"display": "",
		"description": "How much damage this unit deals per hit.",
		"icon": preload("res://Assets/damage_icon.png")
	},
	"UNIT_RANGE": {
		"title": "Range",
		"display": "",
		"description": "How far this unit can attack from.",
		"icon": preload("res://Assets/range_icon.png")
	},
	"UNIT_HITRATE": {
		"title": "Hitrate",
		"display": "",
		"description": "How often this unit can attack.",
		"icon": preload("res://Assets/cooldown_icon.png")
	},
	"UNIT_SPEED": {
		"title": "Speed",
		"display": "",
		"description": "How fast this unit travels.",
		"icon": preload("res://Assets/speed_icon.png")
	},
	"UNIT_RADIUS": {
		"title": "Radius",
		"display": "",
		"description": "How large the AOE of attacks are.",
		"icon": preload("res://Assets/radius.png")
	},
	"FROST": {
		"title": "Frost",
		"display": "",
		"description": "{STATUS_EFFECT_LABEL}. Frozen units move 33% slower per stack of frost.",
		"icon": preload("res://Assets/frost_icon.png")
	},
	"BURN": {
		"title": "Burn",
		"display": "",
		"description": "{STATUS_EFFECT_LABEL}. Burning units take 0.5 damage per second per stack",
		"icon": preload("res://Assets/burn_icon.png")
	},
	"BLEED": {
		"title": "Bleed",
		"display": "",
		"description": "{STATUS_EFFECT_LABEL}: Bleeding units take 0.5 more extra flat damage on hit per stack of bleed",
		"icon": preload("res://Assets/bleed_icon.png")
	},
	"CURSED": {
		"title": "Cursed",
		"display": "",
		"description": "{STATUS_EFFECT_LABEL}: Cursed units take 20% more damage per stack of curse.",
		"icon": preload("res://Assets/cursed_icon.png")
	},
	"POISON": {
		"title": "Poison",
		"display": "",
		"description": "{STATUS_EFFECT_LABEL}: Poisoned units take 5% max HP of damage per second per stack.",
		"icon": preload("res://Assets/poison_icon.png"),
	},
	"STATUS_EFFECT_LABEL": {
		"title": "Status",
		"display": "[Status]",
		"description": "A temporary modifier that affects a unit or tower's stats. Statuses do not stack cumulatively, instead, the highest stack count and highest duration win out.",
		"icon": null,
	},
	"RITE_LABEL": {
		"title": "Rite",
		"display": "[Rite]",
		"description": "Powerful, limited-use structures. Complements and enhances your towers' abilities on the field. Cannot be moved once placed.",
		"icon": null,
	},
	"KEYWORD_TUTORIAL": {
		"title": "Keyword",
		"display": "keywords",
		"description": "Like this one!",
		"icon": null,
	},
	"SETTLEMENT": {
		"title": "Settlement",
		"display": "Settlement",
		"description": "Terrain type on which {T_GENERATOR|label=Villages} are built.",
		"icon": preload("res://Assets/ruins_placeholder.png"),
	}
}
var TOOLTIP_PANEL: PackedScene = load("res://UI/_tooltip_panel.tscn")

var _regex: RegEx

func _ready():
	_verify_keywords()
	
	# initialize regex for parsing {KEYWORD} patterns
	_regex = RegEx.new()
	_regex.compile("\\{([^}]+)\\}") 

# the main public API for other scripts to query
# now supports dynamic lookup for T_ (tower) and R_ (relic) prefixes
func get_keyword_data(keyword: String) -> Dictionary:
	var upper_key: String = keyword.to_upper()
	
	# 1. check static keywords first
	if KEYWORDS.has(upper_key):
		return KEYWORDS[upper_key]
		
	# 2. check for tower prefix
	if upper_key.begins_with("T_"):
		return _resolve_tower_data(upper_key.trim_prefix("T_"))
		
	if upper_key.begins_with("U_"):
		return _resolve_unit_data(upper_key.trim_prefix("U_"))
		
	# 3. check for relic prefix
	if upper_key.begins_with("R_"):
		return _resolve_relic_data(upper_key.trim_prefix("R_"))
		
	return {}

# converts text with {MARKERS} into rich bbcode
func parse_text_for_bbcode(text: String) -> String:
	if text.is_empty():
		return ""
		
	var parsed_text: String = text
	var matches: Array[RegExMatch] = _regex.search_all(text)

	# we use a dictionary to avoid processing the same keyword twice in one string.
	var processed_keys: Dictionary = {}
	
	for match_result in matches:
		var full_placeholder: String = match_result.get_string(0) # e.g. {GOLD}
		var content: String = match_result.get_string(1) # e.g. FLUX
		
		if processed_keys.has(full_placeholder):
			continue
		processed_keys[full_placeholder] = true
		
		#parse parameters
		var parts: PackedStringArray = content.split("|")
		var keyword: String = parts[0] # the first part, which should be the keyword (ie UNIT_HP)
		var params: Dictionary = {}
		for i: int in range(1, parts.size()): #omit the keyword
			var param_str: String = parts[i]
			var parameter_split = param_str.split("=")
			if parameter_split.size() == 2:
				params[parameter_split[0]] = parameter_split[1]
				# eg "size=32" -> ("size", "32") -> {size: 32}
			else:
				pass
		
		# verify data exists before linking
		var data: Dictionary = get_keyword_data(keyword)
		if not data.is_empty():
			# build the inner content (image + title)
			var inner_content: String = ""
			
			if data.has("icon") and data.icon != null:
				var tex: Texture2D = data.icon
				var target_icon_size: int = ICON_SIZE
				if params.has("icon_size"):
					target_icon_size = int(params.icon_size)
				
				var icon_size_x: float = tex.get_width()
				var icon_size_y: float = tex.get_height()
				var scale: float = ((target_icon_size / icon_size_y) + (target_icon_size / icon_size_x)) * 0.5
				# ensure resource exists and has a path for BBCode to find it
				if tex.resource_path != "":
					# add image tag followed by a space
					inner_content += "[img=%sx%s]%s[/img]" % [icon_size_x * scale, icon_size_y * scale, tex.resource_path]
			
			# add the text title
			if params.has("label"):
				inner_content += params.label # manual input fields supersede
			elif data.has("display"):
				inner_content += data.display
			else:
				inner_content += data.title
				
			var color_code = "blue" #default
			if params.has("color"):
				color_code = params.color
			
			#wrap the combined content in the URL and Color tags
			var bbcode_link: String = "[color=%s][url=%s]%s[/url][/color]" % [color_code, keyword, inner_content]
			#replaced text with parsed text
			parsed_text = parsed_text.replace(full_placeholder, bbcode_link)
		else:
			#cleanup broken tags
			parsed_text = parsed_text.replace(full_placeholder, keyword)
			
	return parsed_text

# helper to fetch tower info from the Towers autoload
func _resolve_tower_data(tower_id_str: String) -> Dictionary:
	# convert string ID (e.g. "CANNON") to enum value
	if not Towers.Type.has(tower_id_str):
		return {}
		
	var type: Towers.Type = Towers.Type.get(tower_id_str)
	var prototype: Tower = Towers.get_tower_prototype(type)
	
	var desc: String = "" 
	if prototype and not prototype.stat_displays.is_empty():
		for stat_display: StatDisplayInfo in prototype.stat_displays:
			var value: Variant = Inspector.apply_display_modifiers(Inspector.get_stat_value_from_instance(prototype, stat_display), stat_display)
			desc += stat_display.label + " " + str(value) + stat_display.suffix
			desc += "\n"
		
	desc += Towers.get_tower_description(type)
	
	# build dictionary to match standard keyword format
	return {
		"title": Towers.get_tower_name(type),
		"labels": "[Tower]",
		"description": desc,
		"icon": Towers.get_tower_icon(type)
	}
	
func _resolve_unit_data(unit_id_str: String) -> Dictionary:
	# convert string ID (e.g. "CANNON") to enum value
	if not Units.Type.has(unit_id_str):
		return {}
		
	var type: Units.Type = Units.Type.get(unit_id_str)
	var prototype: Unit = Units.get_unit_prototype(type)
	var desc: String = ""
	if prototype and not Units.get_stat_displays(type).is_empty():
		for stat_display: StatDisplayInfo in Units.get_stat_displays(type):
			var value: Variant = Inspector.apply_display_modifiers(Inspector.get_stat_value_from_unit(prototype, stat_display), stat_display)
			desc += stat_display.label + " " + str(value) + stat_display.suffix
			desc += "\n"
		
	desc += Units.get_unit_description(type)
	
	# build dictionary to match standard keyword format
	return {
		"title": Units.get_unit_name(type),
		"labels": "[Unit]",
		"description": desc,
		"icon": null,
	}

# helper to fetch relic info
func _resolve_relic_data(relic_id_str: String) -> Dictionary:
	var type: RelicData.Type = int(relic_id_str)
	var relic: RelicData = Relics.relics[type]
	
	if not relic:
		return {}
	
	return {
		"title": relic.title,
		"labels": "[Relic]",
		"description": relic.description,
		"icon": relic.icon,
	}

func _verify_keywords():
	for keyword: String in KEYWORDS:
		var keyword_data: Dictionary = KEYWORDS[keyword]
		assert(keyword_data.has(&"title"))
		assert(keyword_data.has(&"description"))
		assert(keyword_data.has(&"icon"))
