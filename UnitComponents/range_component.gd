extends UnitComponent
class_name RangeComponent

#responsible for identifying targets for towers
var area: Area2D ##rangefinding area

var _enemies_in_range: Array[Unit] = []
@export var targeting_mode: TargetingMode = TargetingMode.CLOSEST

#if this is set, get_target will prioritize it over all other logic.
var priority_target_override: Unit = null

var attack_component: AttackComponent
var modifiers_component: ModifiersComponent
var _status_targeting_preferences: Dictionary[Attributes.Status, int] = {}

enum TargetingMode {
	CLOSEST,
	MOST_HEALTH,
	FASTEST,
	SCATTER,
	STRONGEST
}

func _ready() -> void:
	set_process(false)

func inject_components(_attack_component: AttackComponent, _modifiers_component: ModifiersComponent) -> void:
	attack_component = _attack_component
	modifiers_component = _modifiers_component

	if attack_component == null or modifiers_component == null:
		return

	area = Area2D.new() #generate range area
	area.name = "Range"
	#set detection bitmasks
	area.collision_layer = 0
	area.collision_mask = Hitbox.get_mask(not unit.hostile)
	area.monitoring = true
	area.monitorable = false

	var shape := CircleShape2D.new()
	shape.radius = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child.call_deferred(collision)

	unit.add_child.call_deferred(area)

	modifiers_component.stat_changed.connect(func(attr: Attributes.id): #change radius of detection area to fit range
		if not attr == Attributes.id.RANGE:
			return

		shape.radius = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)
	)

	area.area_entered.connect(func(enemy_area_candidate: Area2D):
		if not enemy_area_candidate is Hitbox:
			return

		if enemy_area_candidate.unit == null:
			return

		if enemy_area_candidate.unit.hostile == unit.hostile: #same affiliation
			return

		_enemies_in_range.append(enemy_area_candidate.unit)
	)

	area.area_exited.connect(func(exiting_area_candidate: Area2D):
		if not exiting_area_candidate is Hitbox:
			return

		if exiting_area_candidate.unit == null:
			return

		_enemies_in_range.erase(exiting_area_candidate.unit)
	)

#checks hard constraints only (death, despawned, incorporeal).
#soft constraints (like overkill) are handled in the selection logic.
func is_target_valid(target_unit) -> bool:
	if not is_instance_valid(target_unit):
		return false

	if not is_instance_valid(target_unit.movement_component) or not is_instance_valid(target_unit.health_component):
		return false

	if target_unit is Tower and target_unit.current_state == Tower.State.RUINED:
		return false

	if target_unit.incorporeal:
		return false

	if target_unit.abstractive:
		return false

	return true

#checks if priority (ie priority and non overkilled targets) are available
func are_priority_targets_available() -> bool:
	if is_instance_valid(priority_target_override):
		if _enemies_in_range.has(priority_target_override):
			return true

	var global_priority_target: Unit = Targeting.get_priority_target()
	if is_target_valid(global_priority_target) and _enemies_in_range.has(global_priority_target):
		return true

	for enemy: Unit in _enemies_in_range:
		if not is_target_valid(enemy):
			continue

		if not Targeting.is_unit_overkilled(enemy):
			return true
	return false

func add_status_targeting_preference(status: Attributes.Status) -> void: ##adds one source asking this range component to prefer enemies with a status
	var current_count: int = int(_status_targeting_preferences.get(status, 0))
	_status_targeting_preferences[status] = current_count + 1

func remove_status_targeting_preference(status: Attributes.Status) -> void: ##removes one source of a status preference without clearing overlapping rites
	if not _status_targeting_preferences.has(status):
		return

	var next_count: int = _status_targeting_preferences[status] - 1
	if next_count <= 0:
		_status_targeting_preferences.erase(status)
		return

	_status_targeting_preferences[status] = next_count

func get_target() -> Unit:
	if _enemies_in_range.is_empty():
		return null

	if is_instance_valid(priority_target_override):
		if _enemies_in_range.has(priority_target_override):
			return priority_target_override

	if unit.attack_only_when_blocked:
		return null

	var global_priority_target: Unit = Targeting.get_priority_target()
	if is_target_valid(global_priority_target) and _enemies_in_range.has(global_priority_target):
		return global_priority_target

	var primary_candidates: Array[Unit] = []
	var overkilled_candidates: Array[Unit] = []

	for enemy: Unit in _enemies_in_range:
		if not is_target_valid(enemy):
			continue

		if Targeting.is_unit_overkilled(enemy):
			overkilled_candidates.append(enemy)
		else:
			primary_candidates.append(enemy)

	if not primary_candidates.is_empty():
		return _find_best_candidate(primary_candidates)
	elif not overkilled_candidates.is_empty():
		return _find_best_candidate(overkilled_candidates)

	return null

func get_targets(count: int) -> Array[Unit]:
	if _enemies_in_range.is_empty():
		return []

	var priority_candidates: Array[Unit] = []
	var valid_candidates: Array[Unit] = []
	var overkilled_candidates: Array[Unit] = []
	var global_priority_target: Unit = Targeting.get_priority_target()

	for enemy: Unit in _enemies_in_range:
		if not is_target_valid(enemy):
			continue

		if enemy == global_priority_target:
			priority_candidates.append(enemy)
			continue

		if Targeting.is_unit_overkilled(enemy):
			overkilled_candidates.append(enemy)
		else:
			valid_candidates.append(enemy)

	if valid_candidates.size() < count:
		var needed: int = count - valid_candidates.size()
		valid_candidates.append_array(overkilled_candidates.slice(0, needed))

	if valid_candidates.is_empty():
		return priority_candidates.slice(0, count)

	if targeting_mode == TargetingMode.SCATTER:
		var preferred_candidates: Array[Unit] = _filter_preferred_targets(valid_candidates)
		var other_candidates: Array[Unit] = _filter_unpreferred_targets(valid_candidates)
		preferred_candidates.shuffle()
		other_candidates.shuffle()
		valid_candidates = priority_candidates + preferred_candidates + other_candidates
		return valid_candidates.slice(0, count)

	valid_candidates.sort_custom(func(a: Unit, b: Unit):
		var a_preferred: bool = _matches_status_targeting_preference(a)
		var b_preferred: bool = _matches_status_targeting_preference(b)
		if a_preferred != b_preferred:
			return a_preferred

		match targeting_mode:
			TargetingMode.CLOSEST:
				var dist_a: float = (a.position - unit.position).length_squared()
				var dist_b: float = (b.position - unit.position).length_squared()
				return dist_a < dist_b
			TargetingMode.MOST_HEALTH:
				return a.health_component.health > b.health_component.health
			TargetingMode.STRONGEST:
				return a.strength > b.strength
			TargetingMode.FASTEST:
				var speed_a: float = float(a.get_stat(Attributes.id.MAX_SPEED))
				var speed_b: float = float(b.get_stat(Attributes.id.MAX_SPEED))
				return speed_a > speed_b
		return false
	)

	valid_candidates = priority_candidates + valid_candidates
	return valid_candidates.slice(0, count)

#helper function to reduce code repetition.
#iterates the list once and applies the comparison logic based on the current mode.
func _find_best_candidate(candidates: Array[Unit]) -> Unit:
	if candidates.is_empty():
		return null

	if targeting_mode == TargetingMode.SCATTER:
		var preferred_candidates: Array[Unit] = _filter_preferred_targets(candidates)
		if not preferred_candidates.is_empty():
			return preferred_candidates.pick_random()
		return candidates.pick_random()

	var best_unit: Unit = candidates[0]

	#minor optimization: if there's only one choice, don't bother looping
	if candidates.size() == 1:
		return best_unit

	for candidate: Unit in candidates:
		var is_better: bool = false
		var candidate_preferred: bool = _matches_status_targeting_preference(candidate)
		var best_preferred: bool = _matches_status_targeting_preference(best_unit)
		if candidate_preferred != best_preferred:
			is_better = candidate_preferred
			if is_better:
				best_unit = candidate
			continue

		match targeting_mode:
			TargetingMode.CLOSEST:
				var dist_best: float = (best_unit.position - unit.position).length_squared()
				var dist_cand: float = (candidate.position - unit.position).length_squared()
				is_better = dist_cand < dist_best

			TargetingMode.MOST_HEALTH:
				is_better = candidate.health_component.health > best_unit.health_component.health

			TargetingMode.STRONGEST:
				is_better = candidate.strength > best_unit.strength

			TargetingMode.FASTEST:
				var speed_best: float = float(best_unit.get_stat(Attributes.id.MAX_SPEED))
				var speed_cand: float = float(candidate.get_stat(Attributes.id.MAX_SPEED))
				is_better = speed_cand > speed_best

		if is_better:
			best_unit = candidate

	return best_unit

func _matches_status_targeting_preference(target_unit: Unit) -> bool: ##returns whether this target satisfies any active status preference
	if _status_targeting_preferences.is_empty():
		return false

	if not is_instance_valid(target_unit) or not is_instance_valid(target_unit.modifiers_component):
		return false

	for status: Attributes.Status in _status_targeting_preferences:
		if target_unit.modifiers_component.has_status(status):
			return true

	return false

func _filter_preferred_targets(candidates: Array[Unit]) -> Array[Unit]: ##returns candidates matching at least one status preference
	var output: Array[Unit] = []
	for candidate: Unit in candidates:
		if _matches_status_targeting_preference(candidate):
			output.append(candidate)
	return output

func _filter_unpreferred_targets(candidates: Array[Unit]) -> Array[Unit]: ##returns candidates not matching any status preference
	var output: Array[Unit] = []
	for candidate: Unit in candidates:
		if not _matches_status_targeting_preference(candidate):
			output.append(candidate)
	return output

func get_save_data() -> Dictionary:
	return {
		"targeting_mode" = targeting_mode,
	}
