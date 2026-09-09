extends Resource
class_name BossEnemyStackData

@export var unit_type: Units.Type = Units.Type.BASIC ##enemy type spawned by this boss subwave row
@export_range(0, 999, 1) var count: int = 1 ##number of this enemy type spawned by this boss subwave row

func to_wave_enemy_stack() -> Array: ##converts this typed row to the compact stack shape used by existing wave preview helpers
	return [unit_type, count]
