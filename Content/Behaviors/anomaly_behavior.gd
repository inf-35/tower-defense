extends Behavior
class_name AnomalyBehavior

# --- state machine ---
enum State { INACTIVE, CHARGING, COMPLETE }
var _current_state: State = State.INACTIVE

# --- configuration ---
const DETECTION_RADIUS: float = 13.0

# --- internal state ---
@export var _anomaly_data: AnomalyData:
	set(a):
		_anomaly_data = a

var _waves_charged: int = 0
var _detection_area: Area2D
var _has_fed_this_wave: bool = false

# called by the base Behavior class after initial_state is set
func start() -> void:
	_setup_detection_area()
	
	#connect to phase signals to manage the per-wave logic
	Phases.wave_cycle_started.connect(_on_wave_started)
	Phases.wave_ended.connect(_on_wave_ended)
	
	#setup states
	_enter_state(State.INACTIVE)

func _setup_detection_area() -> void:
	_detection_area = Area2D.new()
	_detection_area.name = "ProximitySensor"
	unit.add_child(_detection_area)
	
	var shape := CircleShape2D.new()
	shape.radius = DETECTION_RADIUS
	
	var collision := CollisionShape2D.new()
	collision.shape = shape
	_detection_area.add_child(collision)
	
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = Hitbox.get_mask(true) #scan for enemies
	_detection_area.monitorable = false
	_detection_area.monitoring = true
	
	_detection_area.area_entered.connect(_on_area_entered)

func _enter_state(new_state: State) -> void:
	if _current_state == new_state: return
	_current_state = new_state
	
	match _current_state:
		State.INACTIVE:
			# dormant
			# e.g., Low opacity, closed eye
			if is_instance_valid(unit.graphics):
				unit.graphics.modulate = Color(0.5, 0.5, 0.5, 0.8)
			
		State.CHARGING:
			# active
			if is_instance_valid(unit.graphics):
				unit.graphics.modulate = Color(1.0, 0.5, 1.0, 1.0) # Pink glow
			
			# Optional: Play a sound effect indicating it "caught" the wave essence
			# Audio.play_sound(ID.Sounds.ANOMALY_ACTIVATE, unit.global_position)
			
		State.COMPLETE:
			# apply reward
			RewardService.apply_reward(_anomaly_data.reward)
			
			# cleanup signals
			if _detection_area.area_entered.is_connected(_on_area_entered):
				_detection_area.area_entered.disconnect(_on_area_entered)
			Phases.wave_cycle_started.disconnect(_on_wave_started)
			Phases.wave_ended.disconnect(_on_wave_ended)
			
			# cleanup[ unit
			await get_tree().create_timer(0.2).timeout
			if is_instance_valid(unit):
				unit.died.emit(HitReportData.blank_hit_report) #triggers removal


func _on_area_entered(area: Area2D) -> void:
	if _current_state == State.COMPLETE or _has_fed_this_wave:
		return

	if not area is Hitbox:
		return

	_has_fed_this_wave = true
	_enter_state(State.CHARGING)

func _on_wave_started(_wave_number: int) -> void:
	if _current_state == State.COMPLETE: return
	
	# New wave, reset feeding status
	_has_fed_this_wave = false
	_enter_state(State.INACTIVE)

func _on_wave_ended(_wave_number: int) -> void:
	if _current_state == State.COMPLETE: return
	
	# if we successfully charged this wave (an enemy passed by), increment progress
	if _has_fed_this_wave:
		_waves_charged += 1
		
		# Feedback
		print("Anomaly absorbed wave energy. Progress: %d/%d" % [_waves_charged, _anomaly_data.waves_to_charge])
		
		if _waves_charged >= _anomaly_data.waves_to_charge:
			_enter_state(State.COMPLETE)
	
	UI.update_unit_state.emit(unit)

# --- Inspector Data ---
func get_display_data() -> Dictionary:
	if not is_instance_valid(_anomaly_data): return {}

	var waves_left: int = _anomaly_data.waves_to_charge - _waves_charged
	return {
		ID.UnitState.WAVES_LEFT_IN_PHASE: waves_left,
		ID.UnitState.REWARD_PREVIEW: _anomaly_data.reward,
		# Optional: Tell the UI if we are currently active this wave
		"is_active_this_wave": _has_fed_this_wave 
	}
