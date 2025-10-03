#a store for stringname identifiers
class_name ID

class UnitState:
	const WAVES_LEFT_IN_PHASE: StringName = &"waves_left_in_phase" #for breach
	const SEED_DURATION_WAVES: StringName = &"seed_duration_waves"
	const AMPLIFIER_MODIFIER: StringName = &"modifier" #for amplifier
	const ANOMALY_WAVES_LEFT: StringName = &"anomaly_waves_left" #for anomaly
	
	const CAPACITY_GENERATED: StringName = &"capacity_generated"
	const LAST_CAPACITY_GENERATION: StringName = &"last_capacity_generation"
	
class TerrainGen:
	const SEED_DURARTION_WAVES: StringName = &"seed_duration_waves" #used for pregen feature initial state definition
	
class Rewards:
	const TOWER_TYPE: StringName = &"tower_type"
	const FLUX_AMOUNT: StringName = &"flux_amount"
	
class Particles:
	const ENEMY_HIT_SPARKS: StringName = &"enemy_hit_sparks"
	const ENEMY_DEATH_SPARKS: StringName = &"enemy_death_sparks"
	
class Sounds:
	const ENEMY_HIT_SOUND: StringName = &"enemy_hit_sound"
	const BUTTON_HOVER_SOUND: StringName = &"button_hover_sound"
	const BUTTON_CLICK_SOUND: StringName = &"button_click_sound"
