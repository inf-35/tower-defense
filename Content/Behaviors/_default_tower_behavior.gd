# default_tower_behavior.gd
extends Behavior
class_name DefaultTowerBehavior
# --- state machine ---
enum State { READY, WIND_UP}
var _current_state: State = State.READY
# --- state ---
var _locked_target: Unit = null
var _in_anticipation: bool = false ##whether the unit is in an anticipation state

func start() -> void:
	if not is_instance_valid(animation_player):
		return
	
	animation_player.animation_started.connect(func(anim_name: StringName):
		if anim_name == &"attack_windup":
			_in_anticipation = true
		elif anim_name == &"attack":
			_in_anticipation = false
	)
	
	Waves.wave_ended.connect(func(_wave_number: int):
		await Clock.await_game_time(1.0)
		if _in_anticipation:
			_play_animation(&"attack_windup", -1.0)
	)

# this is the main update loop, called by the unit's _process function
func update(_delta: float) -> void:
	# ensure all required components are valid
	if not is_instance_valid(attack_component) or not is_instance_valid(range_component):
		return

	var attack_cooldown: float = attack_component.current_cooldown
	# state transition logic
	match _current_state:
		State.READY:
			# in the ready state, we are constantly searching for a target
			var target: Unit = range_component.get_target()
			if is_instance_valid(target):
				# target found! transition to the wind-up state
				_enter_state(State.WIND_UP, target)
		State.WIND_UP:
			# check if our locked target has become invalid
			if not range_component.is_target_valid(_locked_target):
				# abort the attack and go back to searching
				_enter_state(State.READY)
				return
			# check if we are targeting a non-priority target and there are priority targets available
			if Targeting.is_unit_overkilled(_locked_target) and range_component.are_priority_targets_available():
				_enter_state(State.READY)
				return
			
			# turn towards target
			#TODO: optimisation: predict once, and have the target unit tell us if it renavigates
			var predicted_target_pos: Vector2 = AttackComponent.predict_intercept_position(unit, _locked_target, attack_component.attack_data.projectile_speed, false, attack_cooldown)
			var direction_to_target: Vector2 = (predicted_target_pos - turret.global_position)
			var target_angle: float = direction_to_target.angle() - graphics.global_rotation
			var angle_diff: float = abs(angle_difference(turret.rotation, target_angle))
			var required_turn_speed: float = angle_diff / maxf(attack_cooldown, 0.01)
			_rotate_turret(target_angle, required_turn_speed * Clock.game_delta)
			# if the wind-up timer finishes, execute the attack
			if _is_attack_possible():
				_attack(_locked_target)
				# transition back to the ready state
				_enter_state(State.READY)

# this function handles all state transitions and effects
func _enter_state(new_state: State, target: Unit = null) -> void:
	_current_state = new_state
	
	match _current_state:
		State.READY:
			_locked_target = null

		State.WIND_UP:
			_locked_target = target
			
			# command the unit to play its anticipation animation
			if (not is_instance_valid(animation_player)) or not animation_player.has_animation(&"attack_windup"):
				return
			var animation_length: float = unit.animation_player.get_animation(&"attack_windup").length
			await Clock.create_game_timer(attack_component.current_cooldown - animation_length).timeout
			_play_animation(&"attack_windup") #TODO: implement animation compress/stretching

func _attack(_target: Unit):
	# snap towards target
	var predicted_target_pos: Vector2 = AttackComponent.predict_intercept_position(unit, _locked_target, attack_component.attack_data.projectile_speed, false, attack_component.current_cooldown)
	var direction_to_target: Vector2 = (predicted_target_pos - turret.global_position)
	turret.rotation = direction_to_target.angle() - graphics.global_rotation
	_play_animation(&"attack")
	attack_component.attack(_locked_target)

#helper for rotation logic
func _rotate_turret(target_angle: float, turn_step: float) -> void:
	var angle_diff: float = angle_difference(turret.rotation, target_angle)
	turret.rotation += clamp(angle_diff, -turn_step, turn_step)
