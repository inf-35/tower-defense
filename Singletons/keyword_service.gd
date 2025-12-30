# keyword_service.gd (Autoload Singleton)
extends Node

var ICON_SIZE: int = 25
# master dictionary for static keywords
const KEYWORDS: Dictionary[String, Dictionary] = {
	"FLUX": {
		"title": "",
		"description": "The primary currency used for building and upgrading towers.",
		"icon": preload("res://Assets/gold_icon.png"),
	},
	"PLAYER_HP": {
		"title": "",
		"description": "Player Health. If this reaches 0, the run ends.",
		"icon": preload("res://Assets/hp_icon.png"),
	},
	"CAPACITY" : {
		"title": "",
		"description": "Player Capacity",
		"icon": preload("res://Assets/capacity_icon.png"),
	},
	"BREACH": {
		"title": "Breach",
		"description": "An active enemy spawn point. Will close after a set number of waves.",
		"icon": null
	},
	"REWARD": {
		"title": "Anomaly",
		"description": "A special Breach that will offer a choice of powerful rewards when its wave is cleared.",
		"icon": null
	},
	"FROST": {
		"title": "Frost",
		"description": "This unit moves and attacks at a glacial rate.",
		"icon": null,
	},
	"BURN": {
		"title": "Burn",
		"description": "This unit is burning and takes 0.5 damage per second per stack",
		"icon": null,
	},
}

var TOOLTIP_PANEL: PackedScene = load("res://UI/_tooltip_panel.tscn")

var _regex: RegEx

func _ready():
	_verify_keywords()
	
	# initialize regex for parsing {KEYWORD} patterns
	_regex = RegEx.new()
	_regex.compile("\\{([A-Z0-9_]+)\\}")

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
	
	# iterate backwards to avoid invalidating string indices if we were modifying in place,
	# but since we are doing replace string-wise, simple iteration is fine.
	# we use a dictionary to avoid processing the same keyword twice in one string.
	var processed_keys: Dictionary = {}
	
	for match_result in matches:
		var full_placeholder: String = match_result.get_string(0) # e.g. {FLUX}
		var keyword: String = match_result.get_string(1) # e.g. FLUX
		
		if processed_keys.has(keyword):
			continue
		processed_keys[keyword] = true
		
		# verify data exists before linking
		var data: Dictionary = get_keyword_data(keyword)
		if not data.is_empty():
			# build the inner content (image + title)
			var inner_content: String = ""
			
			if data.has("icon") and data.icon != null:
				var tex: Texture2D = data.icon
				# ensure resource exists and has a path for BBCode to find it
				if tex.resource_path != "":
					# add image tag followed by a space
					inner_content += "[img=%sx%s]%s[/img]" % [ICON_SIZE, ICON_SIZE, tex.resource_path]
			
			# add the text title
			inner_content += data.title
			
			#wrap the combined content in the URL and Color tags
			var bbcode_link: String = "[color=blue][url=%s]%s[/url][/color]" % [keyword, inner_content]
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
		
	var type: int = Towers.Type.get(tower_id_str)
	
	# build dictionary to match standard keyword format
	return {
		"title": Towers.get_tower_name(type),
		"description": Towers.get_tower_description(type),
		"icon": Towers.get_tower_icon(type)
	}

# helper to fetch relic info
func _resolve_relic_data(relic_id_str: String) -> Dictionary:
	var relic: RelicData = Relics.relics.get(relic_id_str)
	
	if not relic:
		return {}
	
	return {
		"title": relic.title,
		"description": relic.description,
		"icon": relic.icon,
	}

func _verify_keywords():
	for keyword: String in KEYWORDS:
		var keyword_data: Dictionary = KEYWORDS[keyword]
		assert(keyword_data.has(&"title"))
		assert(keyword_data.has(&"description"))
		assert(keyword_data.has(&"icon"))
