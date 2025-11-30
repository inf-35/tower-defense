extends UnitComponent
class_name RangeComponent

# responsible for identifying targets for towers
var area: Area2D ## rangefinding area

var _enemies_in_range: Array[Unit] = []
@export var targeting_mode: TargetingMode = TargetingMode.CLOSEST

# if this is set, get_target will prioritize it over all other logic.
var priority_target_override: Unit = null

var attack_component: AttackComponent
var modifiers_component: ModifiersComponent

enum TargetingMode {
	CLOSEST,
	MOST_HEALTH,
	FASTEST,
	SCATTER,
}

func _ready() -> void:
	set_process(false)

func inject_components(_attack_component: AttackComponent, _modifiers_component: ModifiersComponent) -> void:
	attack_component = _attack_component
	modifiers_component = _modifiers_component
	
	if attack_component == null or modifiers_component == null:
		return
	
	area = Area2D.new() # generate range area
	area.name = "Range"
	unit.add_child.call_deferred(area)
	
	var shape := CircleShape2D.new()
	shape.radius = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)

	var collision := CollisionShape2D.new()
	collision.shape = shape
	area.add_child.call_deferred(collision)
	
	# set detection bitmasks
	area.collision_layer = 0
	area.collision_mask = 0b0000_0010 if unit.hostile else 0b0000_0001
	area.monitoring = true
	area.monitorable = false
	
	modifiers_component.stat_changed.connect(func(attr: Attributes.id): # change radius of detection area to fit range
		if not attr == Attributes.id.RANGE:
			return

		shape.radius = attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.RANGE)
	)
		
	area.area_entered.connect(func(enemy_area_candidate: Area2D):
		if not enemy_area_candidate is Hitbox:
			return
			
		if enemy_area_candidate.unit == null:
			return

		if enemy_area_candidate.unit.hostile == unit.hostile: # same affiliation
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

# checks hard constraints only (death, despawned, incorporeal).
# soft constraints (like overkill) are handled in the selection logic.
func is_target_valid(target_unit) -> bool:
	if not is_instance_valid(target_unit):
		return false
		
	if not is_instance_valid(target_unit.movement_component) or not is_instance_valid(target_unit.health_component):
		return false
		
	#if Targeting.is_unit_overkilled(target_unit):
		#return false

	if target_unit.incorporeal:
		return false
		
	return true

#checks if priority (ie priority and non overkilled targets) are available
func are_priority_targets_available() -> bool:
	if is_instance_valid(priority_target_override):
		if _enemies_in_range.has(priority_target_override):
			return true
	
	for enemy: Unit in _enemies_in_range:
		if not is_target_valid(enemy):
			continue
		
		if not Targeting.is_unit_overkilled(enemy):
			return true
	return false
		
func get_target() -> Unit:
	if _enemies_in_range.is_empty():
		return null
	
	# handle priority override
	if is_instance_valid(priority_target_override):
		if _enemies_in_range.has(priority_target_override):
			return priority_target_override
	
	# sort targets into two buckets: preferred and fallback
	var primary_candidates: Array[Unit] = []
	var overkilled_candidates: Array[Unit] = []
	
	for enemy in _enemies_in_range:
		if not is_target_valid(enemy):
			continue
			
		# check soft constraint
		if Targeting.is_unit_overkilled(enemy):
			overkilled_candidates.append(enemy)
		else:
			primary_candidates.append(enemy)
	# logic: try to find a target in the primary list.
	# if primary list is empty, try the overkilled list.
	# if both are empty, return null
	if not primary_candidates.is_empty():
		return _find_best_candidate(primary_candidates)
	elif not overkilled_candidates.is_empty():
		return _find_best_candidate(overkilled_candidates)
	
	return null

# helper function to reduce code repetition.
# iterates the list once and applies the comparison logic based on the current mode.
func _find_best_candidate(candidates: Array[Unit]) -> Unit:
	if candidates.is_empty():
		return null
		
	# scatter is special because it doesn't compare units against each other,
	# it just grabs one arbitrarily.
	if targeting_mode == TargetingMode.SCATTER:
		return candidates.pick_random()
	
	var best_unit: Unit = candidates[0]
	
	# minor optimization: if there's only one choice, don't bother looping
	if candidates.size() == 1:
		return best_unit

	for candidate: Unit in candidates:
		var is_better: bool = false
		
		match targeting_mode:
			TargetingMode.CLOSEST:
				# compare squared distances (faster than sqrt)
				var dist_best = (best_unit.position - unit.position).length_squared()
				var dist_cand = (candidate.position - unit.position).length_squared()
				is_better = dist_cand < dist_best
				
			TargetingMode.MOST_HEALTH:
				is_better = candidate.health_component.health > best_unit.health_component.health
				
			TargetingMode.FASTEST:
				# assuming movement_component has a speed variable.
				# uncomment if valid, or adjust to match your variable names.
				# is_better = candidate.movement_component.speed > best_unit.movement_component.speed
				pass

		if is_better:
			best_unit = candidate
			
	return best_unit
