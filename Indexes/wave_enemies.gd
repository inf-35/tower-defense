class_name WaveEnemies #stores enemies per wave, see Waves for the spawning logic.

enum { #this is an anonymous copy of the units enum found in Units
	BASIC,
	BUFF,
	ARCHER
}

const MAX_WAVE_IMPLEMENTED: int = 10
const BASE_SCALING_FACTOR: float = 1.1

const enemies_per_wave: Dictionary[int, Array] = {
	1: [
		[BASIC, 1],
	],
	2: [
		[BASIC, 9],
	],
	3 : [
		[BASIC, 12],
	],
	4 : [
		[BASIC, 10],
		[BUFF, 2],
	],
	5 : [
		[BASIC, 12],
		[BUFF, 4],
	],
	6 : [
		[BASIC, 14],
		[BUFF, 6],
	],
	7 : [
		[BASIC, 16],
		[BUFF, 10],
	],
	8 : [
		[BASIC, 20],
		[BUFF, 12],
	],
	9 : [
		[BASIC, 24],
		[BUFF, 14],
	],
	10 : [
		[BASIC, 20],
		[BUFF, 10],
		[ARCHER, 4],
	]
}

const conversion_sheet: Dictionary[Array, int] = {
	[BASIC, 2]: BUFF
}

static func get_enemies_for_wave(wave: int) -> Array:
	if enemies_per_wave.has(wave): #no need to implement scaling
		return enemies_per_wave[wave].duplicate(true)
		
	var base_wave: int = ((wave - 1) % MAX_WAVE_IMPLEMENTED) + 1
	var base_wave_enemies: Array = enemies_per_wave[base_wave].duplicate(true)
	
	var scaling_factor: float = pow(BASE_SCALING_FACTOR, (wave - base_wave)) #base_scaling^(dW)
	for enemy_stack: Array in base_wave_enemies:
		enemy_stack[1] = floori(enemy_stack[1] * scaling_factor)
	
	return base_wave_enemies

static func get_enemy_count(enemies: Array) -> int:
	var counter: int = 0
	for enemy_stack: Array in enemies:
		counter += enemy_stack[1]
	return counter

static func get_wave_length_for_enemies(enemies: int) -> float:
	return (0.0 + pow(float(enemies), 1.0/3.0)) #4 + cbrt(enemies)
	
