# WaveTimeline.gd
extends Control
class_name WaveTimeline

# --- state ---
# this component no longer owns the current_wave state, it mirrors it from Phases.gd
var _current_wave: int = 0
var _loaded_pip_count: int = 0

# --- configuration ---
const PIPS_LOADED_BUFFER: int = 15 # number of pips to show in the timeline
var SPACING_BETWEEN_PIPS: int = 20:
	set(new_spacing):
		SPACING_BETWEEN_PIPS = new_spacing
		_update_pips_style()

# --- node references ---
@export var pips_container: HBoxContainer

# --- scenes ---
const TIMELINE_PIP_SCENE: PackedScene = preload("res://UI/pip.tscn")

func _ready() -> void:
	# connect to the game's phase manager to sync state
	# note: Phases should emit this signal at game start and when preparing a new wave cycle
	UI.start_wave.connect(_on_wave_cycle_started)
	
	_update_pips_style()
	# initial setup call to populate the timeline when the game loads
	_on_wave_cycle_started(Phases.current_wave_number)

# called by the Phases manager to sync the timeline's state
func _on_wave_cycle_started(new_wave_number: int) -> void:
	print("NEW WAVE NUMBER: ", new_wave_number)
	self._current_wave = new_wave_number
	# if a tween isn't active, this is an initial setup or a hard reset
	if _loaded_pip_count == 0:
		_regenerate_all_pips()
	# otherwise a wave just ended, trigger the scrolling animation
	else:
		print("yep")
		_progress_wave()

func _update_pips_style() -> void:
	pips_container.add_theme_constant_override(&"separation", SPACING_BETWEEN_PIPS)

func _regenerate_all_pips() -> void:
	# clear any pips that might already exist
	for child: Node in pips_container.get_children():
		child.queue_free()
	_loaded_pip_count = 0
	
	# generate a fresh set of pips based on the current game state
	_fill_pip_buffer()
	
	# update the first pip to visually represent the 'current' wave
	if pips_container.get_child_count() > 0:
		var current_pip: TimelinePip = pips_container.get_child(0)
		if is_instance_valid(current_pip):
			current_pip.set_is_current(true)

# intelligently loads pips from the external source until the buffer is full
func _fill_pip_buffer() -> void:
	# loop until the number of loaded pips meets our desired buffer size
	while _loaded_pip_count < PIPS_LOADED_BUFFER:
		# calculate the wave number for the next pip we need to load
		var wave_to_load: int = _current_wave + _loaded_pip_count
		
		# get wave type from the central plan in the phases manager
		var wave_type: Phases.WaveType = Phases.get_wave_type(wave_to_load)
		
		# instantiate and configure the pip
		var pip: TimelinePip = TIMELINE_PIP_SCENE.instantiate()
		pip.setup(wave_to_load, wave_type) # pass wave data to the pip
		
		pips_container.add_child(pip)
		_loaded_pip_count += 1

# public function to trigger the animation
func _progress_wave() -> void:
	if pips_container.get_child_count() <= 1:
		return

	var current_pip: TimelinePip = pips_container.get_child(0)
	if not is_instance_valid(current_pip):
		return # exit if the pip is somehow invalid
	current_pip.set_is_current(true)

	# calculate the dynamic distance to travel
	# this is the core advantage of using a tween
	var pip_width: float = current_pip.size.x
	var distance_to_travel: float = (pip_width + SPACING_BETWEEN_PIPS)
	var target_position: Vector2 = Vector2(-distance_to_travel, pips_container.position.y)
	
	# create and configure the tween
	var tween: Tween = create_tween()
	# set the animation's properties (target node, property, end value, duration)
	tween.tween_property(pips_container, "position", target_position, 0.5)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)

	# connect the tween's completion signal to our cleanup function
	tween.finished.connect(_on_tween_finished)

# renamed from _on_animation_finished to reflect the new source
func _on_tween_finished() -> void:
	# remove the leftmost pip (which is now off-screen)
	if pips_container.get_child_count() > 0:
		var old_pip: Node = pips_container.get_child(0)
		pips_container.remove_child(old_pip)
		old_pip.queue_free()
		_loaded_pip_count -= 1
	
	# reset the container's position for the next animation
	# this snap is invisible to the user because the pips have been rearranged
	pips_container.position = Vector2.ZERO

	# generate a new pip to refill the buffer
	_fill_pip_buffer()
	
	# update the appearance of the new 'current' pip
	if pips_container.get_child_count() > 0:
		var new_current_pip: TimelinePip = pips_container.get_child(0)
		if is_instance_valid(new_current_pip):
			new_current_pip.set_is_current(true)
