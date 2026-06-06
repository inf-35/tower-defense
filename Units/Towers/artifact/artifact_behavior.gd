extends Behavior
class_name ArtifactBehavior

#--- state machine ---
enum State { HIDDEN, UNLOCKING, COMPLETE }
var _current_state: State = State.HIDDEN

var reward: Reward
@export var waves_to_unlock: int = 1

#--- internal state ---
var _waves_passed: int = 0

func _ready() -> void:
	Run.phases.wave_ended.connect(_on_wave_ended)

func start() -> void:
	_enter_state(State.UNLOCKING)

func _enter_state(new_state: State) -> void:
	if _current_state == new_state: return
	_current_state = new_state

	match _current_state:
		State.HIDDEN:
			#visuals: dim / dusty
			if is_instance_valid(unit.graphics):
				unit.graphics.modulate = Color(0.6, 0.6, 0.6, 1.0)

		State.UNLOCKING:
			#visuals: active / glowing
			pass

			#vfx: play "activation" sound/particle
			#VFXManager.play_vfx(ID.Particles.CONSTRUCTION_PUFF, unit.global_position, Vector2.UP)

		State.COMPLETE:
			#grant loot
			RewardService.apply_reward(reward)

			#visual feedback
			#spawn a text popup or distinct sound
			print("Artifact cracked open! Reward granted.")

			#3. cleanup
			Run.phases.wave_ended.disconnect(_on_wave_ended)
			unit.queue_free()

func _on_wave_ended(_wave_number: int) -> void:
	if _current_state != State.UNLOCKING:
		return

	#increment progress
	_waves_passed += 1

	#update ui (inspector)
	UI.update_unit_state.emit(unit)

	#check completion
	if _waves_passed >= waves_to_unlock:
		_enter_state(State.COMPLETE)

#--- ui integration ---

func get_display_data() -> Dictionary:
	if _current_state == State.HIDDEN:
		return {
			"status": "Dormant",
			"info": "Build adjacent to activate."
		}
	elif _current_state == State.UNLOCKING:
		var left = waves_to_unlock - _waves_passed
		return {
			"status": "Excavating...",
			ID.UnitState.WAVES_LEFT_IN_PHASE: left, #reusing existing id for consistent icon usage
			ID.UnitState.REWARD_PREVIEW: reward
		}

	return {}
