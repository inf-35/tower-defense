extends Resource
class_name BossSubwaveData

@export var mandatory_duration: float = 20.0 ##minimum combat time before this boss subwave can clear
@export var enemy_stacks: Array[BossEnemyStackData] = [] ##typed minion rows spawned during this boss subwave

func get_enemy_stacks() -> Array[Array]: ##returns a defensive copy of the minion roster for spawning or previews
	var output: Array[Array] = []
	for enemy_stack: BossEnemyStackData in enemy_stacks:
		if enemy_stack == null or enemy_stack.count <= 0:
			continue
		output.append(enemy_stack.to_wave_enemy_stack())
	return output

func get_enemy_count() -> int: ##counts planned minions in the same compact stack format used by ordinary waves
	var total: int = 0
	for enemy_stack: BossEnemyStackData in enemy_stacks:
		if enemy_stack == null:
			continue
		total += enemy_stack.count
	return total
