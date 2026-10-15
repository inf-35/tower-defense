class_name BossEncounters

enum Type {
	NONE,
	OLIPHANT,
	WAR_BALLOON,
}

const OLIPHANT_DATA: BossEncounterData = preload("res://Content/BossEncounters/oliphant/oliphant_boss_encounter.tres")
const WAR_BALLOON_DATA: BossEncounterData = preload("res://Content/BossEncounters/war_balloon_boss_encounter.tres")

static var _encounter_cache: Dictionary[Type, BossEncounterData] = {}

static func get_encounter_data(encounter_type: Type) -> BossEncounterData: ##returns cached authored boss data for a scheduled encounter id
	if encounter_type == Type.NONE:
		return null
	if not _encounter_cache.has(encounter_type):
		_encounter_cache[encounter_type] = _load_encounter_data(encounter_type)
	return _encounter_cache[encounter_type]

static func get_preview_enemy_stacks(encounter_type: Type, subwave_index: int = 0, include_boss: bool = true) -> Array[Array]: ##returns boss plus current subwave minions in ordinary wave stack format for existing previews
	var encounter_data: BossEncounterData = get_encounter_data(encounter_type)
	if encounter_data == null:
		return []

	var preview_stacks: Array[Array] = []
	if include_boss:
		preview_stacks.append([encounter_data.boss_type, 1])

	var subwave: BossSubwaveData = encounter_data.get_subwave(subwave_index)
	if subwave != null:
		preview_stacks.append_array(subwave.get_enemy_stacks())
	var encounter_logic: BossEncounterLogic = encounter_data.create_logic()
	preview_stacks.append_array(encounter_logic.get_preview_enemy_stacks(subwave_index))
	return WaveEnemies._consolidate_enemy_list(_flatten_enemy_stacks(preview_stacks))

static func _load_encounter_data(encounter_type: Type) -> BossEncounterData: ##loads the authored boss data resource for a scheduled encounter id
	match encounter_type:
		Type.OLIPHANT:
			return OLIPHANT_DATA
		Type.WAR_BALLOON:
			return WAR_BALLOON_DATA
	return null

static func _flatten_enemy_stacks(enemy_stacks: Array[Array]) -> Array[Units.Type]: ##converts stacked preview data into the format expected by WaveEnemies consolidation
	var output: Array[Units.Type] = []
	for enemy_stack: Array in enemy_stacks:
		if enemy_stack.size() < 2:
			continue
		var unit_type: Units.Type = enemy_stack[0]
		var unit_count: int = int(enemy_stack[1])
		for _i: int in range(unit_count):
			output.append(unit_type)
	return output
