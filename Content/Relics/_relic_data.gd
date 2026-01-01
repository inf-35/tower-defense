# relic_data.gd
extends Resource
class_name RelicData

# --- targeting rules ---
enum TargetType {
	ALL_TOWERS,
	PLAYER,
	ALL_ENEMIES,
	SPECIFIC_TOWER_TYPE,
	SPECIFIC_ELEMENT
	# add more specific target types as needed
}

enum Type {
	AMBUSH,
	BROKEN_MIRROR,
	COMMON_COLD,
	CONTAGION,
	ENFILADE,
	FIERY_SPIRIT,
	HYPOTHERMIA,
	INFERNO,
	MONEY_MARKET,
	NATURES_SPIRIT,
	PERMAFROST,
	SEPSIS,
	STUMBLING_BLOCKS,
	SUBPRIME,
	TRANCE,
	WILDERNESS,
	WINTERS_SPIRIT
}

@export var type: Type
@export var target_type: TargetType

# used only if target_type is SPECIFIC_TOWER_TYPE
@export var specific_tower_type: Towers.Type
@export var specific_element: Towers.Element
# --- effect data ---p
# each relic contains a modifier prototype that defines its stat changes
@export var modifier_prototypes: Array[ModifierDataPrototype] ##modifiers that are applied to all satisfying towers (see specific_tower_type)
@export var global_effect: EffectPrototype
@export var active_effect_scene: PackedScene ##for active global effects, scene is instantiated as child of the player->global modifier singleton
# --- presentation data for ui ---
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D
