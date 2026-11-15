extends DefaultTowerBehavior

const SUNRING_MIN_TURN_DEGREES: float = 60.0
const SUNRING_MAX_TURN_DEGREES: float = 400.0
const SUNRING_FIRE_PAUSE: float = 0.14

@export var sunring: Sprite2D ##rotates independently of the aiming ring between shots

var _sunring_tween: Tween

func start() -> void: ##binds the animation to game speed before the first cooldown
	super.start()
	Clock.speed_changed.connect(_on_speed_changed)
	attach()

func attach() -> void: ##resumes tracking and starts a turn over the remaining cooldown
	_turn_sunring(0.0)

func detach() -> void: ##stops both rings when the tower deactivates
	_enter_state(State.READY)
	if _sunring_tween != null:
		_sunring_tween.kill()
		_sunring_tween = null

func _attack(_target: Unit) -> void: ##fires at the current priority target with a matching starstruck particle trail
	var target: Unit = range_component.get_target()
	if not is_instance_valid(target):
		return

	var shot_color: Color = Attributes.status_effects[Attributes.Status.STARSTRUCK].overlay_color
	VFXManager.play_swirl_line(unit.global_position, target.global_position, shot_color, 7.0, 0.36, 10.0)
	super._attack(target)
	if not unit.disabled and not unit.is_queued_for_deletion():
		_turn_sunring(SUNRING_FIRE_PAUSE)

func _turn_sunring(pause_seconds: float) -> void: ##holds at firing, then eases a signed relative turn over the next cooldown
	if _sunring_tween != null:
		_sunring_tween.kill()
		_sunring_tween = null
	var cooldown: float = attack_component.current_cooldown
	if cooldown <= 0.0 or not is_instance_valid(sunring):
		return

	var pause_duration: float = minf(pause_seconds, cooldown * 0.25)
	var turn_degrees: float = randf_range(SUNRING_MIN_TURN_DEGREES, SUNRING_MAX_TURN_DEGREES)
	if randf() < 0.5:
		turn_degrees = -turn_degrees
	sunring.rotation_degrees = wrapf(sunring.rotation_degrees, -180.0, 180.0)
	var target_degrees: float = sunring.rotation_degrees + turn_degrees
	_sunring_tween = create_tween().set_speed_scale(Clock.speed_multiplier)
	_sunring_tween.tween_property(sunring, ^"rotation_degrees", target_degrees, cooldown - pause_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(pause_duration)

func _on_speed_changed(multiplier: float) -> void: ##keeps the current turn in sync with the game's clock
	if _sunring_tween != null and _sunring_tween.is_valid():
		_sunring_tween.set_speed_scale(multiplier)
