# default_tower_behavior.gd
extends Behavior
class_name DefaultTowerBehavior

# --- internal state ---
# the state machine has been removed. the behavior is now continuous.
var _current_target: Unit = null
var target_pos: Vector2

# the main update loop, now a continuous tracking and firing cycle
func update(delta: float) -> void:
	# use the base class's cooldown variable as our master timer
	_cooldown += Clock.game_delta

	# --- 1. Target Acquisition and Validation ---
	# if our current target is invalid (dead or out of range), find a new one.
	if not is_instance_valid(_current_target) or not range_component.is_target_valid(_current_target):
		_current_target = range_component.get_target()
	
	# if there are no valid targets at all, do nothing else this frame.
	if not is_instance_valid(_current_target):
		return

	# --- 2. Turret Rotation Logic ---
	if is_instance_valid(turret):
		var cooldown_left: float = max(attack_component.get_stat(modifiers_component, attack_component.attack_data, Attributes.id.COOLDOWN) - _cooldown, 0.0)
		# we predict the intercept position once, which is cheap enough.
		target_pos = attack_component.predict_intercept_position(unit, _current_target, attack_component.attack_data.projectile_speed, false, cooldown_left)
		var direction_to_target: Vector2 = (target_pos - turret.global_position).normalized()
		var target_angle: float = direction_to_target.angle()
		
		# --- Dynamic Turn Speed Calculation ---
		# if we have time left on the cooldown, calculate the exact speed needed to arrive on time.
		cooldown_left = max(cooldown_left, 0.05) #small minimum turning time
		var angle_diff: float = abs(angle_difference(turret.rotation, target_angle))
		var required_turn_speed: float = angle_diff / cooldown_left
		_rotate_turret(target_angle, required_turn_speed * Clock.game_delta)


	# --- 3. Firing Logic ---
	# the firing decision is now completely decoupled from aiming.
	# it fires if the cooldown is ready and we have a valid target.
	if _is_attack_possible():
		# use the base class helper. it will get the latest target and reset the cooldown for us.
		# we pass the already-predicted position to the attack function.
		if _attempt_attack_with_override(_current_target, target_pos):
			# after firing, immediately find the next target to start turning towards
			_current_target = range_component.get_target()

# new helper function in the base class for this pattern
func _attempt_attack_with_override(target: Unit, intercept_override: Vector2) -> bool:
	if not _is_attack_possible() or not is_instance_valid(target):
		return false
		
	attack_component.attack(target, intercept_override)
	_cooldown = 0.0
	unit.queue_redraw()
	return true

# new helper for rotation logic
func _rotate_turret(target_angle: float, turn_step: float) -> void:
	var angle_diff: float = angle_difference(turret.rotation, target_angle)
	turret.rotation += clamp(angle_diff, -turn_step, turn_step)
