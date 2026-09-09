#a store for stringname identifiers
class_name ID

class UnitState: ##for ui/attribute resolution
	const WAVES_LEFT_IN_PHASE: StringName = &"waves_left_in_phase" #for breach, anomaly, and all wave/phase-based towers
	const SEED_DURATION_WAVES: StringName = &"seed_duration_waves"
	const AMPLIFIER_MODIFIER: StringName = &"modifier" #for amplifier
	const REWARD_PREVIEW: StringName = &"reward_preview"
	const BREACH_WAVE_PREVIEW: StringName = &"breach_wave_preview"

	const CAPACITY_GENERATED: StringName = &"capacity_generated"
	const LAST_CAPACITY_GENERATION: StringName = &"last_capacity_generation"

class UnitMeta: ##for meta attribute
	const IS_IMPORTANT: StringName = &"is_important" ##is a unit "important"? see unitdata
	const IS_BOSS: StringName = &"is_boss" ##marks the persistent enemy owned by a boss encounter
	const BOSS_ENCOUNTER_TYPE: StringName = &"boss_encounter_type" ##stores the owning boss encounter id on the boss unit
	const BOSS_MINION_ENCOUNTER_TYPE: StringName = &"boss_minion_encounter_type" ##stores the owning boss encounter id on tracked minions

class TerrainGen:
	const SEED_DURATION_WAVES: StringName = &"seed_duration_waves" #used for pregen feature initial state definition

class Rewards:
	const TOWER_TYPE: StringName = &"tower_type"
	const FLUX_AMOUNT: StringName = &"flux_amount"
	const RELIC: StringName = &"relic"

class Particles:
	const ENEMY_HIT_SPARKS: StringName = &"enemy_hit_sparks"
	const ENEMY_DEATH_SPARKS: StringName = &"enemy_death_sparks"

class Sounds:
	const ENEMY_HIT_SOUND: StringName = &"enemy_hit_sound"
	const BUTTON_HOVER_SOUND: StringName = &"button_hover_sound"
	const BUTTON_CLICK_SOUND: StringName = &"button_click_sound"
	const TOWER_PLACED_SOUND: StringName = &"tower_placed_sound"
	
	const COIN_PICKUP_SOUND: StringName = &"coin_pickup_sound"
	const COIN_SPEND_SOUND: StringName = &"coin_spend_sound"
	const ARROW_FIRE_SOUND: StringName = &"arrow_fire_sound"
	const ARROW_THUNK_SOUND: StringName = &"arrow_thunk_sound"
	const CANNON_FIRE_SOUND: StringName = &"cannon_fire_sound"
	const AOE_FIRE_SOUND: StringName = &"aoe_fire_sound"
	const FLAME_FIRE_SOUND: StringName = &"flame_fire_sound"
	const MUSIC_COMBAT_LOOP: StringName = &"combat_loop"
	const AMBIENCE_BIRDSONG: StringName = &"ambience_birdsong"
	const AMBIENCE_WOODS: StringName = &"ambience_woods"
