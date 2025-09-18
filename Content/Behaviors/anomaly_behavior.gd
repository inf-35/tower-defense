# anomaly_behavior.gd
extends Behavior
class_name AnomalyBehavior

# --- state machine ---
enum State { INACTIVE, CHARGING, COMPLETE }
var _current_state: State = State.INACTIVE

# --- internal state ---
@export var _anomaly_data: AnomalyData
var _waves_charged: int = 0

# called by the base Behavior class after initial_state is set
func start() -> void:
	# connect to the signals that drive the state machine
	(unit as Tower).adjacency_updated.connect(_on_adjacency_updated)
	Phases.wave_ended.connect(_on_wave_ended)
	
	# perform an initial check in case the anomaly is spawned already fulfilling the condition
	await get_tree().process_frame # wait a frame for adjacencies to be calculated
	if is_instance_valid(unit):
		_on_adjacency_updated(References.island.get_adjacent_towers(unit.tower_position))

func _enter_state(new_state: State) -> void:
	if _current_state == new_state: return
	_current_state = new_state
	# print("Anomaly entering state: ", State.keys()[_current_state]) # for debugging

	match _current_state:
		State.INACTIVE:
			# when we become inactive, reset any charge progress
			_waves_charged = 0
			# here you would command the unit's graphics to show a "dormant" visual state
			
		State.CHARGING:
			# here you would command the unit's graphics to "power up"
			pass
			
		State.COMPLETE:
			# --- the payoff ---
			# 1. command the reward service to apply the reward
			RewardService.apply_reward(_anomaly_data.reward)
			
			# 2. disconnect signals to stop processing events
			(unit as Tower).adjacency_updated.disconnect(_on_adjacency_updated)
			Phases.wave_ended.disconnect(_on_wave_ended)
			
			# 3. command the graphics to show a "depleted" state
			# 4. after a delay, remove the anomaly from the map
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(unit):
				unit.died.emit() # this triggers cleanup in the Island script

# checks if the adjacency condition is met
func _is_charge_condition_met(adjacencies: Dictionary[Vector2i, Tower]) -> bool:
	for tower: Tower in adjacencies.values():
		# the condition is met if at least one adjacent tower is player-controlled
		if is_instance_valid(tower) and not tower.hostile:
			return true
	return false

# signal handler for when neighboring towers change
func _on_adjacency_updated(adjacencies: Dictionary[Vector2i, Tower]) -> void:
	if _current_state == State.COMPLETE: return
	print("anomaly adjacency updated")
	var condition_met: bool = _is_charge_condition_met(adjacencies)
	
	if condition_met and _current_state == State.INACTIVE:
		_enter_state(State.CHARGING)
	elif not condition_met and _current_state == State.CHARGING:
		_enter_state(State.INACTIVE)

# signal handler for when a combat wave is successfully completed
func _on_wave_ended(wave_number: int) -> void:
	if _current_state != State.CHARGING: return
	
	_waves_charged += 1
	print("charged!", _waves_charged," / ",_anomaly_data.waves_to_charge)
	if _waves_charged >= _anomaly_data.waves_to_charge:
		_enter_state(State.COMPLETE)

# override to provide UI data to the inspector
func get_display_data() -> Dictionary:
	if not is_instance_valid(_anomaly_data): return {}
	
	var waves_left: int = _anomaly_data.waves_to_charge - _waves_charged
	return {
		ID.UnitState.ANOMALY_WAVES_LEFT: waves_left
	}
