class_name WaveEnemies

const SCRIPTED_WAVES: Dictionary[int, Array] = {
	# Example: Wave 1 is just 5 Basics (Tutorial)
	1: [
		[Units.Type.BASIC, 1000],
	],
	2: [
		[Units.Type.BASIC, 8],
	],
	3: [
		[Units.Type.BASIC, 4],
		[Units.Type.BUFF, 3],
	],
	4: [
		[Units.Type.BASIC, 5],
		[Units.Type.BUFF, 4],
	],
	5 : [
		[Units.Type.BASIC, 6],
		[Units.Type.DRIFTER, 5],
	],
	6 : [
		[Units.Type.BASIC, 6],
		[Units.Type.BUFF, 2],
		[Units.Type.HEALER, 1],
		[Units.Type.DRIFTER, 2],
	],
	7 : [
		[Units.Type.TROLL, 3],
		[Units.Type.BASIC, 12],
	],
	8 : [
		[Units.Type.TROLL, 3],
		[Units.Type.BASIC, 8],
		[Units.Type.BUFF, 2],
		[Units.Type.HEALER, 2],
		[Units.Type.DRIFTER, 3],
	],
	9 : [
		[Units.Type.BASIC, 16],
		[Units.Type.ARCHER, 4],
	],
	10 : [
		[Units.Type.TROLL, 3],
		[Units.Type.BASIC, 14],
		[Units.Type.HEALER, 4],
		[Units.Type.DRIFTER, 5],
		[Units.Type.ARCHER, 4],
		[Units.Type.BUFF, 4],
	],
	11 : [
		[Units.Type.WARRIOR, 18],
		[Units.Type.BUFF, 10],
	],
	12 : [
		[Units.Type.DRIFTER, 5],
		[Units.Type.WARRIOR, 18],
		[Units.Type.HEALER, 4],
		[Units.Type.BUFF, 10],
	],
	13 : [
		[Units.Type.DRIFTER, 5],
		[Units.Type.WARRIOR, 18],
		[Units.Type.TROLL, 4],
		[Units.Type.HEALER, 4],
		[Units.Type.BUFF, 10],
	],
	14 : [
		[Units.Type.TROLL, 10],
		[Units.Type.HEALER, 4],
	],
	15 : [
		[Units.Type.WARRIOR, 30],
		[Units.Type.BUFF, 25],
		[Units.Type.HEALER, 8],
		[Units.Type.ARCHER, 6],
	],
	16 : [
		[Units.Type.TROLL, 6],
		[Units.Type.WARRIOR, 24],
		[Units.Type.HEALER, 6],
		[Units.Type.DRIFTER, 20],
		[Units.Type.ARCHER, 5],
		[Units.Type.BUFF, 10],
	]
}
# --- unit catalog ---
# this is the master data definition for all spawnable units.
# cost: the budget points required to spawn one unit.
# tags: descriptors used by the director to make intelligent choices.
enum WaveModifier {
	SWARM,
	ELITE,
	SIEGE,
	MIXED_ARMS
}

const UNIT_DATA: Dictionary[Units.Type, Dictionary] = {
	Units.Type.BASIC:   {"cost": 15, "tags": [&"GRUNT", &"MELEE"], "wave": 0},
	Units.Type.BUFF:    {"cost": 20, "tags": [&"SUPPORT"], "wave": 2},
	Units.Type.DRIFTER: {"cost": 30, "tags": [&"GRUNT", &"MELEE"], "wave": 4},
	Units.Type.TROLL: {"cost": 60, "tags": [&"SUPPORT", &"SIEGE"], "wave": 6},
	Units.Type.ARCHER: {"cost": 40, "tags": [&"SUPPORT"], "wave": 8},
}

# --- director configuration ---
const BASE_BUDGET: float = 40.0
const BUDGET_PER_WAVE: float = 24.0
const QUADRATIC_BUDGET_SCALING: float = 1.8

# the main public function, now a procedural generator
static func get_enemies_for_wave(wave: int) -> Array[Array]:
	if SCRIPTED_WAVES.has(wave):
		var output: Array[Array]
		output.assign(SCRIPTED_WAVES[wave])
		return output

	# 1. get the wave modifier from the central game director
	var wave_type: Phases.WaveType = Phases.get_wave_type(wave)
	var modifier: WaveModifier
	
	match wave_type:
		Phases.WaveType.NORMAL:
			modifier = WaveModifier.MIXED_ARMS
		Phases.WaveType.BOSS:
			modifier = WaveModifier.ELITE
		Phases.WaveType.SURGE:
			modifier = WaveModifier.SIEGE
	
	# 2. calculate the base budget for this wave
	var budget: float = BASE_BUDGET + (wave * BUDGET_PER_WAVE) + QUADRATIC_BUDGET_SCALING * (wave ** 2) 
	
	# 3. get the pool of available units and apply modifier rules
	var unit_pool: Array[Units.Type] = UNIT_DATA.keys() as Array[Units.Type]
	unit_pool = _get_units_by_wave(unit_pool, wave)
	
	# apply modifier effects
	match modifier:
		WaveModifier.SWARM:
			budget *= 1.5 # larger budget
			# only allow cheap grunt units
			unit_pool = _get_units_by_tag(unit_pool, &"GRUNT")
			unit_pool.append_array(_get_units_by_tag(unit_pool, &"SUPPORT"))
			unit_pool = _get_units_by_max_cost(unit_pool, budget * 0.2)
		WaveModifier.ELITE:
			budget *= 0.7 # smaller budget, but units will be stronger
			# only allow expensive units
			unit_pool = _get_units_by_min_cost(unit_pool, budget * 0.1)
		WaveModifier.SIEGE:
			unit_pool = _get_units_by_tag(unit_pool, &"SIEGE")
		WaveModifier.MIXED_ARMS:
			# no change to budget or pool, but the purchase logic will be different
			pass

	# 4. "spend" the budget to compose the wave
	var composed_wave: Array[Units.Type] = _compose_wave_from_budget(budget, unit_pool, modifier)
	
	# 5. consolidate the raw list into the required [[TYPE, count]] format
	return _consolidate_enemy_list(composed_wave)

# --- private director logic ---

# the core algorithm for spending the budget
static func _compose_wave_from_budget(budget: float, pool: Array[Units.Type], modifier: WaveModifier) -> Array[Units.Type]:
	var budget_remaining: float = budget
	var composed_enemies: Array[Units.Type] = []
	
	# sort the pool by cost so we can always find the cheapest unit
	pool.sort_custom(func(a, b): return UNIT_DATA[a].cost < UNIT_DATA[b].cost)
	if pool.is_empty():
		return []
	
	var cheapest_cost: float = UNIT_DATA[pool[0]].cost
	
	while budget_remaining >= cheapest_cost:
		var unit_to_buy: Units.Type
		# for mixed arms, use a more structured approach
		if modifier == WaveModifier.MIXED_ARMS and randf() < 0.4:
			var ranged_pool: Array = _get_units_by_tag(pool, &"RANGED")
			if not ranged_pool.is_empty():
				unit_to_buy = ranged_pool.pick_random()
			else:
				unit_to_buy = pool.pick_random() # fallback
		else:
			# for other modes, just pick randomly from the allowed pool
			unit_to_buy = pool.pick_random()
		
		var cost: float = UNIT_DATA[unit_to_buy].cost
		
		if budget_remaining >= cost:
			composed_enemies.append(unit_to_buy)
			budget_remaining -= cost
		else:
			# if we can't afford the random pick, try to buy the cheapest unit instead
			var cheapest_unit: Units.Type = pool[0]
			if budget_remaining >= UNIT_DATA[cheapest_unit].cost:
				composed_enemies.append(cheapest_unit)
				budget_remaining -= UNIT_DATA[cheapest_unit].cost
			else:
				# if we can't even afford the cheapest, we're done
				break
				
	return composed_enemies

# consolidates a list like [BASIC, BASIC, ARCHER] into [[BASIC, 2], [ARCHER, 1]]
static func _consolidate_enemy_list(enemies: Array[Units.Type]) -> Array[Array]:
	var counts: Dictionary[Units.Type, int] = {}
	for enemy_type: Units.Type in enemies:
		counts[enemy_type] = counts.get(enemy_type, 0) + 1
	
	var final_list: Array[Array] = []
	for type: Units.Type in counts:
		final_list.append([type, counts[type]])
		
	return final_list
#for debug purposes, translates enemy lists into a human readable format
static func make_readable_enemy_list(enemies: Array[Array]) -> String:
	var output_string: String = ""
	for enemy_stack: Array in enemies:
		output_string += Units.Type.keys()[enemy_stack[0]] + ": " + str(enemy_stack[1]) + ", "
	return output_string

# --- helper functions for filtering the unit pool ---
static func _get_units_by_tag(pool: Array[Units.Type], tag: StringName) -> Array[Units.Type]:
	return pool.filter(func(type): return UNIT_DATA[type].tags.has(tag))
	
static func _get_units_by_wave(pool: Array[Units.Type], wave: int) -> Array[Units.Type]:
	return pool.filter(func(type): return wave >= UNIT_DATA[type].wave)

static func _get_units_by_max_cost(pool: Array[Units.Type], max_cost: int) -> Array[Units.Type]:
	return pool.filter(func(type): return UNIT_DATA[type].cost <= max_cost)
	
static func _get_units_by_min_cost(pool: Array[Units.Type], min_cost: int) -> Array[Units.Type]:
	return pool.filter(func(type): return UNIT_DATA[type].cost >= min_cost)

# --- existing functions ---
static func get_enemy_count(enemies: Array) -> int:
	var counter: int = 0
	for enemy_stack: Array in enemies:
		counter += enemy_stack[1]
	return counter

static func get_wave_length_for_enemies(enemies: int) -> float:
	return (2.0 + pow(float(enemies), 1.0/3.0))
