# relic_data.gd
extends Resource
class_name RelicData

# --- targeting rules ---
enum TargetType {
	ALL_TOWERS,
	PLAYER,
	ALL_ENEMIES,
	SPECIFIC_TOWER_TYPE,
	# add more specific target types as needed
}
@export var target_type: TargetType

# used only if target_type is SPECIFIC_TOWER_TYPE
@export var specific_tower_type: Towers.Type
# --- effect data ---
# each relic contains a modifier prototype that defines its stat changes
@export var modifier_prototype: ModifierDataPrototype
# --- presentation data for ui ---
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D
