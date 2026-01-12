extends Behavior
class_name ArtifactBehavior

# --- State Machine ---
enum State { HIDDEN, UNLOCKING, COMPLETE }
var _current_state: State = State.HIDDEN

var reward: Reward
@export var waves_to_unlock: int = 1

# --- Internal State ---
var _waves_passed: int = 0

func _ready():
	Phases.wave_ended.connect(_on_wave_ended)

func start() -> void:
	_enter_state(State.UNLOCKING)

func _enter_state(new_state: State) -> void:
	if _current_state == new_state: return
	_current_state = new_state
	
	match _current_state:
		State.HIDDEN:
			# Visuals: Dim / Dusty
			if is_instance_valid(unit.graphics):
				unit.graphics.modulate = Color(0.6, 0.6, 0.6, 1.0)
				
		State.UNLOCKING:
			# Visuals: Active / Glowing
			pass
			
			# VFX: Play "Activation" sound/particle
			#VFXManager.play_vfx(ID.Particles.CONSTRUCTION_PUFF, unit.global_position, Vector2.UP)
	
		State.COMPLETE:
			# grant Loot
			RewardService.apply_reward(reward)
			
			# visual feedback
			# Spawn a text popup or distinct sound
			print("Artifact cracked open! Reward granted.")
			
			# 3. Cleanup
			Phases.wave_ended.disconnect(_on_wave_ended)
			unit.queue_free()
	
#func _on_adjacency_updated(adjacencies: Dictionary) -> void:
	#if _current_state != State.HIDDEN:
		#return
	#_check_discovery(adjacencies)

#func _check_discovery(adjacencies: Dictionary) -> void:
	## Logic: Has the player built anything next to me?
	#for tower: Tower in adjacencies.values():
		#if is_instance_valid(tower) and not tower.hostile:
			## Discovery condition met!
			#_enter_state(State.UNLOCKING)
			#return

func _on_wave_ended(_wave_number: int) -> void:
	if _current_state != State.UNLOCKING:
		return
		
	# Increment progress
	_waves_passed += 1
	
	# Update UI (Inspector)
	UI.update_unit_state.emit(unit)
	
	# Check Completion
	if _waves_passed >= waves_to_unlock:
		_enter_state(State.COMPLETE)

# --- UI Integration ---

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
			ID.UnitState.WAVES_LEFT_IN_PHASE: left, # Reusing existing ID for consistent icon usage
			ID.UnitState.REWARD_PREVIEW: reward
		}
		
	return {}
