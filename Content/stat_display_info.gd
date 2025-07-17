extends Resource
class_name StatDisplayInfo
#attaches to a stat, tells inspector how stats should be displayed.
#ordered in arrays in Unit

# The data to fetch.
@export var attribute: Attributes.id = Attributes.id.NULL

# How to display it.
@export var label: String = "" # e.g., "DMG", "RNG"
@export var suffix: String = "" # e.g., "/s"

# For special cases like BPS, Flux, or inverse calculation.
@export var special_modifier: Inspector.DisplayStatModifier = Inspector.DisplayStatModifier.NONE
#see Inspector for special case implementation
