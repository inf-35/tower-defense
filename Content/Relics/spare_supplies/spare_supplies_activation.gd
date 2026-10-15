extends CanvasLayer
class_name SpareSuppliesActivation

signal burst() ##commits the rescue on the frame the icon disappears
signal cancelled() ##releases the pending rescue when its presentation is interrupted

class ScreenBurstParticles extends AoeParticleFieldVFX:
	func _process(delta: float) -> void: ##keeps this hud-only field in real time while reusing the normal aoe layout and drawing
		_age += delta
		if _age >= _lifetime:
			queue_free()
			return
		for particle: AoeParticleFieldVFX.ParticleSpec in _particles:
			particle.position += particle.velocity * delta
		queue_redraw()

@export var icon_control: TextureRect ##detached screen-space copy of the relic icon
@export var burst_info: VFXInfo ##the ordinary aoe particle field, authored yellow for this burst
@export_range(0.1, 3.0, 0.01) var flight_duration: float = 0.85 ##real-time flight and charge duration, unaffected by the paused combat clock
@export_range(1.0, 6.0, 0.05) var final_scale: float = 3.0 ##final icon size relative to its relic-bar size
@export_range(1.0, 40.0, 0.5) var pulse_frequency: float = 18.0 ##scale vibrations per second near the end of the charge
@export_range(0.0, 0.3, 0.01) var pulse_strength: float = 0.08 ##proportional scale vibration, ramping up as the icon grows
@export_range(1.0, 40.0, 0.5) var burst_radius: float = 18.0 ##aoe-space radius controlling the particle budget before scaling the field to the screen icon
@export var vignette_color: Color = Color(1.0, 0.78, 0.08, 0.82) ##golden screen-edge flash at the burst
@export var vignette_intensity_multiplier: float = 2.0 ##multiplier on the normal damage vignette's peak intensity
@export var vignette_duration_multiplier: float = 2.0 ##multiplier on the normal damage vignette's fade duration

var _source_icon: TextureRect
var _source_was_visible: bool = true
var _relic_type: RelicData.Type
var _start_center: Vector2
var _elapsed: float = 0.0
var _saved_speed: float = 1.0
var _owns_pause: bool = false
var _burst_done: bool = false
var _cancelled: bool = false
var _particles: AoeParticleFieldVFX

func _ready() -> void:
	set_process(false)
	Run.run_ending.connect(cancel, CONNECT_ONE_SHOT)

func play(texture: Texture2D, relic_type: RelicData.Type) -> void: ##captures the live relic slot and freezes combat while the screen-space copy charges
	_relic_type = relic_type
	_source_icon = _find_source_icon()
	_start_center = get_viewport().get_visible_rect().get_center()
	icon_control.size = Vector2(64.0, 64.0)
	if is_instance_valid(_source_icon):
		var source_transform: Transform2D = _source_icon.get_global_transform_with_canvas()
		_start_center = source_transform * (_source_icon.size * 0.5)
		icon_control.size = _source_icon.size * source_transform.get_scale().abs()
		_source_was_visible = _source_icon.visible
		_source_icon.hide()
	else:
		push_warning("Spare Supplies: relic-bar icon unavailable; playing the rescue from screen center.")
	icon_control.texture = _source_icon.texture if is_instance_valid(_source_icon) else texture
	icon_control.pivot_offset = icon_control.size * 0.5
	icon_control.position = _start_center - icon_control.size * 0.5
	icon_control.show()
	_saved_speed = Clock.speed_multiplier
	_owns_pause = true
	Clock.speed_changed.connect(_hold_pause)
	Clock.speed_multiplier = 0.0
	set_process(true)

func _input(_event: InputEvent) -> void: ##blocks gameplay, menus, and relic destruction during the short paused reveal
	if _owns_pause:
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void: ##animates the charge and retires the local particle tail independently of combat speed
	if _burst_done:
		if not is_instance_valid(_particles) or _particles.is_queued_for_deletion():
			queue_free()
		return
	_elapsed += delta
	if not is_instance_valid(_source_icon) or _source_icon.is_queued_for_deletion():
		_source_icon = _find_source_icon()
		if is_instance_valid(_source_icon):
			_source_was_visible = _source_icon.visible
			_source_icon.hide()
	var progress: float = clampf(_elapsed / flight_duration, 0.0, 1.0)
	var eased: float = 1.0 - (1.0 - progress) ** 2
	var vibration: float = sin(_elapsed * TAU * pulse_frequency) * pulse_strength * progress ** 2
	icon_control.position = _start_center.lerp(get_viewport().get_visible_rect().get_center(), eased) - icon_control.size * 0.5
	icon_control.scale = Vector2.ONE * lerpf(1.0, final_scale, eased) * (1.0 + vibration)
	if progress >= 1.0:
		_burst()

func _burst() -> void: ##bursts into the shared aoe particles and commits gameplay before restoring the previous speed
	_burst_done = true
	icon_control.hide()
	_particles = ScreenBurstParticles.new()
	add_child(_particles)
	_particles.position = get_viewport().get_visible_rect().get_center()
	_particles.setup_from_info(burst_info, burst_radius)
	_particles.scale = Vector2.ONE * icon_control.size.x * final_scale * 0.75 / burst_radius
	burst.emit()
	if not _cancelled and Run.has_active_run():
		for node: Node in Run.references.island.find_children("*", "Control", true, false):
			if node is PlayerDamageFeedback:
				var feedback := node as PlayerDamageFeedback
				#health ui updates settle first, so an older red flash cannot overwrite the gold.
				feedback.flash_vignette.call_deferred(vignette_color, feedback.peak_intensity * vignette_intensity_multiplier, feedback.fade_duration * vignette_duration_multiplier)
				break
	_release_pause()

func _find_source_icon() -> TextureRect: ##uses the existing pickup target binding and the live relic-slot order, without introducing another ui registry
	if not is_instance_valid(UI.reward_pickup_animator):
		return null
	var display := UI.reward_pickup_animator.relic_target as RelicDisplay
	if not is_instance_valid(display):
		return null
	var relic_index: int = -1
	for index: int in range(Run.player.active_relics.size()):
		if Run.player.active_relics[index].type == _relic_type:
			relic_index = index
			break
	if relic_index < 0:
		return null
	var slot_index: int = 0
	for child: Node in display.get_children():
		if child.is_queued_for_deletion() or not child is RelicSlot:
			continue
		if slot_index == relic_index:
			return (child as RelicSlot).get_icon_control()
		slot_index += 1
	return null

func _hold_pause(speed: float) -> void: ##keeps clock hotkey polling from resuming combat behind the modal animation
	if _owns_pause and not is_zero_approx(speed):
		Clock.speed_multiplier = 0.0

func _release_pause() -> void: ##restores exactly the speed owned by this animation, at most once
	if not _owns_pause:
		return
	_owns_pause = false
	Clock.speed_changed.disconnect(_hold_pause)
	Clock.speed_multiplier = _saved_speed

func cancel() -> void: ##cancels safely before run teardown without applying a rescue to a later run
	if _cancelled:
		return
	_cancelled = true
	set_process(false)
	if not _burst_done:
		cancelled.emit()
	_release_pause()
	queue_free()

func _exit_tree() -> void: ##also releases the pause and hidden source icon if the owner disappears unexpectedly
	if Run.run_ending.is_connected(cancel):
		Run.run_ending.disconnect(cancel)
	if not _burst_done and not _cancelled:
		cancelled.emit()
	if not _burst_done and is_instance_valid(_source_icon):
		_source_icon.visible = _source_was_visible
	_release_pause()
