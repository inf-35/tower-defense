#a store for stringname identifiers
class_name ID

class UnitState: ##for ui/attribute resolution
	const WAVES_LEFT_IN_PHASE: StringName = &"waves_left_in_phase" #for breach, anomaly, and all wave/phase-based towers
	const SEED_DURATION_WAVES: StringName = &"seed_duration_waves"
	const AMPLIFIER_MODIFIER: StringName = &"modifier" #for amplifier
	const REWARD_PREVIEW: StringName = &"reward_preview"
	
	const CAPACITY_GENERATED: StringName = &"capacity_generated"
	const LAST_CAPACITY_GENERATION: StringName = &"last_capacity_generation"
	
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
