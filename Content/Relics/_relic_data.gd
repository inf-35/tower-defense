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
	WINTERS_SPIRIT,
	DYNAMITE,
	MUCOUS_SAC,
	AMETHYST_SKULL,
	ICE_SHARDS,
	WHITE_HOT_IRON,
	EARLY_BIRD,
	MACUAHUITL,
	MOKA_POT,
	PAPER_UMBRELLA,
	PAWN_STRUCTURE,
	TURPID_IDOL,
	SIGNAL_FLAG,
}

@export var type: Type
# --- effect data ---
# each relic contains a modifier prototype that defines its stat changes
@export var modifier_prototypes: Array[GlobalModifierPrototype] ##modifiers that are applied to all satisfying towers (see specific_tower_type)
@export var global_effect: EffectPrototype
@export var active_effect_scene: PackedScene ##for active global effects, scene is instantiated as child of the player->global modifier singleton
# --- presentation data for ui ---
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D = preload("res://Assets/troll.png")
#
func get_save_data() -> Dictionary:
	var save_data: Dictionary = {}
	save_data["type"] = type
	save_data["resource_path"] = resource_path
	#modifier prototypes and TODO: active effect scene are stateless and can be recreated from type
	if global_effect:
		var effect_instance: EffectInstance = Player.global_event_service.get_effect_instance_by_prototype(global_effect)
		var effect_data: Dictionary = effect_instance.effect_prototype.get_save_data(effect_instance)
		
		save_data["global_effect"] = effect_data
	return save_data
	
func load_save_data(save_data: Dictionary) -> void:
	#TODO
	pass
