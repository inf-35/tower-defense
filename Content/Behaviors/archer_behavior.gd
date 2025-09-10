# archer_behavior.gd
extends Behavior
class_name ArcherBehavior

# --- state machine ---
enum State { IDLE, MOVING, ATTACKING }
var _current_state: State = State.IDLE

# --- internal state ---
var _current_target: Unit = null

# this is the main update loop, now a state machine
func update(delta: float) -> void:
	# increment cooldown regardless of state
	_cooldown += delta

	# --- state machine logic ---
	match _current_state:
		State.IDLE, State.MOVING:
			# --- transition condition: can we attack? ---
			if _is_attack_possible():
				_enter_state(State.ATTACKING)
				return

			# --- action: if not attacking, move ---
			# the navigation and movement components handle the actual movement logic
			# we just need to ensure the "move" animation is playing
			if movement_component.velocity.length_squared() > 1:
				if _current_state != State.MOVING:
					_enter_state(State.MOVING)
			else:
				if _current_state != State.IDLE:
					_enter_state(State.IDLE)

		State.ATTACKING:
			# when in the ATTACKING state, this behavior does nothing in the update loop.
			# we are waiting for the animation to finish or for a method track to fire.
			#see _enter_state for attack logic
			pass

func _enter_state(new_state: State) -> void:
	if _current_state == new_state: return
	
	_current_state = new_state
	# print("Archer entering state: ", State.keys()[_current_state]) # for debugging

	match _current_state:
		State.IDLE:
			#_play_animation(&"idle")
			# tell the movement component to stop
			movement_component.speed_control = 1.0
			pass

		State.MOVING:
			#_play_animation(&"move")
			movement_component.speed_control = 1.0
			pass
		State.ATTACKING:
			# --- Telegraph Logic ---
			# stop moving
			movement_component.speed_control = 0.1
			# play the attack animation. the animation itself will handle the timing.
			_play_animation(&"attack")
			_current_target = range_component.get_target() as Unit

# --- animation event handler ---
# this function is called BY THE ANIMATIONPLAYER via a Call Method Track
# at the precise frame the arrow should be released.
func _fire_projectile() -> void:
	print("ea")
	# check if our target is still valid
	if not is_instance_valid(_current_target):
		# if the target died during the wind-up, transition back to idle
		_enter_state(State.IDLE)
		return
	
	# command the stateless attack component to execute the attack
	attack_component.attack(_current_target)
	_cooldown = 0.0 #reset cooldown

# this function is called BY THE ANIMATIONPLAYER at the end of the attack animation
func _on_attack_animation_finished() -> void:
	# after the attack is complete, transition back to a default state
	_enter_state(State.IDLE)
