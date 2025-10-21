extends Behavior
class_name BreachBehavior

# data for this specific breach type, can be exported or come from a resource
@export var seed_duration_waves: int = 2
@export var active_duration_waves: int = Waves.WAVES_PER_EXPANSION_CHOICE * 4 #this ensures we dont accidentally create a scenario where there are no active breaches

enum State { SEED, ACTIVE, CLOSING }
var _current_state: State
var _waves_left_in_state: int

func start() -> void:
	# connect to the game-wide signal to track wave progression
	Phases.wave_cycle_started.connect(_on_wave_cycle_started)
	# start in the initial state
	if seed_duration_waves > 0:
		_enter_state(State.SEED)
	else:
		_enter_state(State.ACTIVE)

func _enter_state(new_state: State) -> void:
	_current_state = new_state
	match _current_state:
		State.SEED:
			_waves_left_in_state = seed_duration_waves
			# command the unit to appear as a seed
			# e.g., unit.graphics.texture = preload("res://seed.png")
			# register with the spawn service, but it won't provide spawn points yet
			SpawnPointService.register_breach(unit, true)

		State.ACTIVE:
			_waves_left_in_state = active_duration_waves
			# command the unit to appear as an active breach
			# e.g., unit.graphics.texture = preload("res://breach.png")
			# the spawn service will now see this as an active spawn point
			SpawnPointService.register_breach(unit, false)

		State.CLOSING:
			# command the unit to play a closing animation and then destroy itself
			unit.died.emit() #killing ourselves triggers the deregistering mechanism

func _on_wave_cycle_started(_wave_number: int) -> void:
	_waves_left_in_state -= 1
	if _waves_left_in_state <= 0:
		if _current_state == State.SEED:
			_enter_state(State.ACTIVE)
		elif _current_state == State.ACTIVE:
			_enter_state(State.CLOSING)
	
	UI.update_unit_state.emit(unit)

# the breach has no active behavior in its _process loop, so update is empty
func update(_delta: float) -> void:
	pass
	
func get_display_data() -> Dictionary:
	# we use StringNames (&) for performance and to avoid typos.
	if _waves_left_in_state == 0: #not initialised
		return { #for preview inspection
			ID.UnitState.WAVES_LEFT_IN_PHASE: seed_duration_waves
		}

	return {
		ID.UnitState.WAVES_LEFT_IN_PHASE: _waves_left_in_state
	}
