extends Resource
class_name StatDisplayInfo
#attaches to a stat, tells inspector how stats should be displayed.
#ordered in arrays in Unit

#the data to fetch.
@export var attribute: Attributes.id = Attributes.id.NULL
@export var dynamic_attribute: StringName = &""

#how to display it.
@export var label: String = "" #e.g., "dmg", "rng"
@export var suffix: String = "" #e.g., "/s"

#for special cases like bps, flux, or inverse calculation.
@export var special_modifier: Inspector.DisplayStatModifier = Inspector.DisplayStatModifier.NONE
#see Inspector for special case implementation
