# WaveTimeline.gd
extends Control
class_name WaveTimeline

# --- configuration ---
const PIPS_LOADED_BUFFER: int = 8 # number of pips to display at once
const SPACING_BETWEEN_PIPS: int = 20
const TWEEN_TIME: float = 1.0

# --- state ---
var _current_wave: int = 0
var _pip_nodes: Array[TimelinePip] = []
var _is_tweening: bool = false

# --- scenes ---
const TIMELINE_PIP_SCENE: PackedScene = preload("res://UI/pip.tscn")

func _ready() -> void:
	# connect to the game's phase manager to sync state
	UI.start_wave.connect(_on_wave_cycle_started)
	UI.update_wave_schedule.connect(_regenerate_all_pips)
	# connect to self resize to trigger repositioning
	self.resized.connect(_update_all_pip_positions)
	# initial setup call
	

# called by the phases manager to sync the timeline's state
func _on_wave_cycle_started(new_wave_number: int) -> void:
	if _is_tweening:
		return
	
	self._current_wave = new_wave_number
	# on first load, regenerate everything instantly
	if _pip_nodes.is_empty():
		_regenerate_all_pips()
	# otherwise, a wave just ended, so trigger the animation
	else:
		_progress_wave()

# this is the single, authoritative function for calculating pip positions
func _calculate_pip_positions(pips: Array[TimelinePip]) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if pips.is_empty():
		return positions
		
	# pre-calculate all visual properties to get an accurate total width
	var pip_visuals: Array[TimelinePip.TimelinePipVisuals] = []
	for pip: TimelinePip in pips:
		pip_visuals.append(pip.get_target_visual_properties())

	var total_width: float = 0.0
	for visuals: TimelinePip.TimelinePipVisuals in pip_visuals:
		# use the actual size from the visuals object, not get_visual_width
		total_width += visuals.size.x
	total_width += max(0, pips.size() - 1) * SPACING_BETWEEN_PIPS

	# determine the x-offset needed to right-align the entire group
	var x_offset: float = self.size.x - total_width
	var current_x: float = x_offset

	# calculate the final top-left position for each pip
	for visuals: TimelinePip.TimelinePipVisuals in pip_visuals:
		var pip_size: Vector2 = visuals.size
		# calculate the center point for this slot
		var center_x: float = current_x + pip_size.x / 2.0
		var center_y: float = 50.0 / 2.0
		# subtract half the size to get the correct top-left position
		positions.append(Vector2(center_x - pip_size.x / 2.0, center_y - pip_size.y / 2.0))
		current_x += pip_size.x + SPACING_BETWEEN_PIPS
		
	return positions

# wrapper function to instantly apply new positions to the active pips
func _update_all_pip_positions() -> void:
	var target_positions: Array[Vector2] = _calculate_pip_positions(self._pip_nodes)
	if target_positions.size() != _pip_nodes.size():
		return # guard against size mismatch
		
	for i: int in _pip_nodes.size():
		_pip_nodes[i].position = target_positions[i]
# generates the initial set of pips without animation
func _regenerate_all_pips() -> void:
	for child: Node in get_children():
		child.queue_free()
	_pip_nodes.clear()

	for i: int in PIPS_LOADED_BUFFER:
		var wave_num: int = _current_wave + i
		var pip: TimelinePip = _create_pip_for_wave(wave_num)
		if i == 0:
			pip.set_is_current(true)
			pip._apply_visuals_instantly()
		_pip_nodes.append(pip)
	# calculate and apply initial positions
	_update_all_pip_positions()

# factory function to create a configured pip
func _create_pip_for_wave(wave_num: int) -> TimelinePip:
	var wave_type: Phases.WaveType = Phases.get_wave_type(wave_num)
	print(Phases.WaveType.keys()[wave_type], " ", wave_num)
	var pip: TimelinePip = TIMELINE_PIP_SCENE.instantiate()
	add_child(pip)
	pip.setup(wave_num, wave_type)
	return pip

# orchestrates the entire wave transition animation
func _progress_wave() -> void:
	_is_tweening = true
	var tween: Tween = create_tween().set_parallel()
	
	# define roles for the animation
	var exiting_pip: TimelinePip = _pip_nodes.front()
	var new_pip: TimelinePip = _create_pip_for_wave(_current_wave + PIPS_LOADED_BUFFER - 1)

	# update states before calculating positions
	for i: int in _pip_nodes.size():
		var pip: TimelinePip = _pip_nodes[i]
		var future_i: int = i - 1
		pip.set_is_current(future_i == 0)
	
	# configure the new pip before animation
	new_pip.modulate.a = 0.0 # start transparent
	
	# create a temporary array representing the final visual state
	var final_pip_order: Array[TimelinePip] = _pip_nodes.slice(1)
	final_pip_order.append(new_pip)
	
	# calculate all final positions using the single authoritative function
	var target_positions: Array[Vector2] = _calculate_pip_positions(final_pip_order)

	# place the new pip just off-screen to the right, ready to tween in
	new_pip.position = Vector2(self.size.x + SPACING_BETWEEN_PIPS, size.y / 2.0)

	# animate all pips shifting to their new final positions
	for i: int in final_pip_order.size():
		var pip_to_shift: TimelinePip = final_pip_order[i]
		pip_to_shift.add_visual_tweens_to(tween)
		tween.parallel().tween_property(pip_to_shift, "position", target_positions[i], TWEEN_TIME)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# fade in the new pip as it moves
	new_pip.fade_to(tween, 1.0)
	
	# animate the exiting pip moving off-screen to the left
	tween.parallel().tween_property(exiting_pip, "position", target_positions[0] - Vector2(SPACING_BETWEEN_PIPS + exiting_pip.size.x * 0.5, exiting_pip.size.y * -0.5), TWEEN_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	exiting_pip.fade_to(tween, 0.0)
	
	tween.finished.connect(func(): _on_tween_finished(exiting_pip, new_pip))

# cleans up state after the animation is complete
func _on_tween_finished(pip_to_destroy: TimelinePip, newly_added_pip: TimelinePip) -> void:
	pip_to_destroy.queue_free()
	# update the internal array to match the visual state
	_pip_nodes.pop_front()
	_pip_nodes.append(newly_added_pip)
	_is_tweening = false
