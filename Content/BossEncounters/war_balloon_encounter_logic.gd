extends BossEncounterLogic
class_name WarBalloonEncounterLogic

const WARRIOR_SQUAD_SIZE: int = 30

var _last_spawned_subwave_index: int = -1

func on_subwave_started(context: BossEncounterContext) -> void: ##drops one warrior squad when the balloon has entered the scene and is positioned
	var boss: Unit = context.get_boss()
	if not is_instance_valid(boss):
		return

	var subwave_index: int = context.get_subwave_index()
	if boss.is_ready:
		_spawn_warrior_squad(context, boss, subwave_index)
		return

	boss.ready.connect(_spawn_warrior_squad.bind(context, boss, subwave_index), CONNECT_ONE_SHOT)

func get_preview_enemy_stacks(_subwave_index: int) -> Array[Array]: ##keeps the encounter-owned squad visible in existing incoming-enemy previews
	var preview_stacks: Array[Array] = [[Units.Type.WARRIOR, WARRIOR_SQUAD_SIZE]]
	return preview_stacks

func _spawn_warrior_squad(context: BossEncounterContext, boss: Unit, subwave_index: int) -> void: ##spawns a tracked squad at the boss's ready world position once per subwave
	if not is_instance_valid(boss) or context.get_boss() != boss:
		return
	if context.get_subwave_index() != subwave_index or _last_spawned_subwave_index == subwave_index:
		return

	_last_spawned_subwave_index = subwave_index
	var spawn_position: Vector2 = boss.global_position
	for _i: int in range(WARRIOR_SQUAD_SIZE):
		context.spawn_minion(Units.Type.WARRIOR, spawn_position)
