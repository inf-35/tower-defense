extends BossEncounterLogic
class_name OliphantEncounterLogic

const RAMP_PER_SECOND: float = 1.0
const MAX_SPEED_MULTIPLIER: float = 10.0

var _speed_modifier: Modifier
var _elapsed: float = 0.0

func on_subwave_started(context: BossEncounterContext) -> void: ##starts a fresh speed ramp so longer minion clears let the oliphant gain ground
	_elapsed = 0.0
	_clear_speed_modifier(context)

	var boss: Unit = context.get_boss()
	if not _can_modify_boss(boss):
		return

	_speed_modifier = Modifier.new(Attributes.id.MAX_SPEED, 1.0, 0.0, -1.0, null, boss.unit_id)
	boss.modifiers_component.add_modifier(_speed_modifier)

func update_subwave(context: BossEncounterContext, delta: float) -> void: ##ramps speed only during active combat and mutates one modifier in place
	if not is_instance_valid(_speed_modifier):
		return

	var boss: Unit = context.get_boss()
	if not _can_modify_boss(boss):
		_speed_modifier = null
		return

	_elapsed += delta
	_speed_modifier.multiplicative = minf(1.0 + (_elapsed * RAMP_PER_SECOND), MAX_SPEED_MULTIPLIER)
	boss.modifiers_component.change_modifier(_speed_modifier)

func on_subwave_cleared(context: BossEncounterContext) -> void: ##removes the ramp before prep so speed pressure resets next subwave
	_clear_speed_modifier(context)

func on_boss_died(context: BossEncounterContext) -> void: ##cleans the mutable ramp if the boss dies during combat
	_clear_speed_modifier(context)

func get_save_data() -> Dictionary: ##persists only the ramp clock; boss prep usually saves with no active ramp
	return {
		"elapsed": _elapsed,
	}

func load_save_data(data: Dictionary) -> void: ##restores the ramp clock for defensive mid-combat save compatibility
	_elapsed = float(data.get("elapsed", 0.0))

func _clear_speed_modifier(context: BossEncounterContext) -> void: ##detaches the active ramp modifier without touching other speed effects
	var boss: Unit = context.get_boss()
	if _can_modify_boss(boss) and is_instance_valid(_speed_modifier):
		boss.modifiers_component.remove_modifier(_speed_modifier)
	_speed_modifier = null

func _can_modify_boss(boss: Unit) -> bool: ##guards boss stat mutation against death, save loading, and teardown timing
	return is_instance_valid(boss) and is_instance_valid(boss.modifiers_component)
