# keyword_service.gd (Autoload Singleton)
extends Node

# the master dictionary for all keywords.
# maybe TODO?: load from CSV or JSON
const KEYWORDS: Dictionary[String, Dictionary] = {
	"FLUX": {
		"title": "Flux",
		"description": "The primary currency used for building and upgrading towers.",
		"icon": null,
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
	}
}

const TOOLTIP_PANEL: PackedScene = preload("res://UI/_tooltip_panel.tscn")

# the main public API for other scripts to query
func get_keyword_data(keyword: String) -> Dictionary:
	return KEYWORDS.get(keyword.to_upper(), null)

# a crucial helper function to make the system easy to use.
# it takes plain text with markers (e.g., "You gain 50 {FLUX}.")
# and converts it into the BBCode that RichTextLabel understands.
func parse_text_for_bbcode(text: String) -> String:
	var parsed_text: String = text
	# in a larger project, you would use a RegEx for more robust parsing.
	# for now, we can iterate through the keys.
	for keyword: String in KEYWORDS:
		# look for the {KEYWORD} pattern
		var placeholder: String = "{%s}" % keyword
		if placeholder in parsed_text:
			var data: Dictionary = KEYWORDS[keyword]
			# replace the placeholder with a formatted [url] tag.
			# the URL content is the keyword itself, which the label will use for lookups.
			var bbcode_link: String = "[color=yellow][url=%s]%s[/url][/color]" % [keyword, data.title]
			print(bbcode_link)
			parsed_text = parsed_text.replace(placeholder, bbcode_link)
	
	return parsed_text

func _verify_keywords():
	for keyword: String in KEYWORDS:
		var keyword_data: Dictionary = KEYWORDS[keyword]
		assert(keyword_data.has(&"title"))
		assert(keyword_data.has(&"description"))
		assert(keyword_data.has(&"icon"))
		
func _ready():
	_verify_keywords()
