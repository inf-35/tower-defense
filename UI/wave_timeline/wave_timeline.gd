extends Control
class_name WaveTimeline

#--- config ---
@export var slot_count: int = 6
@export var slot_container: HBoxContainer
@export var pips_layer: Control
@export var pip_scene: PackedScene

#--- state ---
class TimelineEntry:
	var id: String #unique id for diffing (e.g. "wave5_event0")
	var wave_number: int
	var is_combat: bool
	var subtype: int

var _full_schedule: Array[TimelineEntry] = []
var _active_pips: Array[TimelinePip] = []
var _slots: Array[Control] = []

#tracks the current "head" of the timeline (what is in slot 0)
var _head_index: int = 0

func _ready() -> void:
	await get_tree().process_frame
	for child in slot_container.get_children():
		if child is Control:
			_slots.append(child)
			#child.modulate.a = 0

	_rebuild_full_schedule()
	#connect signals
	UI.start_wave.connect(func(wave): _jump_to_wave(wave, false))
	UI.start_phase.connect(func(wave, combat, subtype): _jump_to_wave(wave, combat, subtype))
	UI.update_wave_schedule.connect(_rebuild_full_schedule)

	UI.tutorial_manager.register_element(TutorialStep.Reference.WAVE_TIMELINE, self)

#--- data generation ---

func _rebuild_full_schedule() -> void:
	_full_schedule.clear()

	#flatten the entire game plan into a linear list
	#this makes "goto" logic trivial (just finding an index)
	for i: int in range(1, Run.phases.FINAL_WAVE + 1):
		var wave_data = Run.phases.wave_plan.get(i)
		if not wave_data: continue

		#a. day events
		for j: int in range(wave_data.day_events.size()):
			var entry = TimelineEntry.new()
			entry.wave_number = i
			entry.is_combat = false
			entry.subtype = wave_data.day_events[j]
			entry.id = "W%d_D%d" % [i, j]
			_full_schedule.append(entry)

		#b. combat
		var entry = TimelineEntry.new()
		entry.wave_number = i
		entry.is_combat = true
		entry.subtype = wave_data.combat_variant
		entry.id = "W%d_C" % i
		_full_schedule.append(entry)

	#initial sync
	_jump_to_wave(Run.phases.current_wave_number, false)

#--- navigation api ---

func _jump_to_wave(wave_number: int, is_combat_start: bool, subtype: int = -1) -> void:
	#find the index in the flattened schedule
	var target_index: int = -1

	for i: int in range(_full_schedule.size()):
		var entry = _full_schedule[i]
		if entry.wave_number == wave_number:
			if is_combat_start and entry.is_combat:
				target_index = i
				break
			elif not is_combat_start and not entry.is_combat:
				if subtype == -1 or subtype == entry.subtype:
					target_index = i
					break

	if target_index == -1: return #not found

	_set_head_index(target_index)

func _advance_one_step() -> void:
	_set_head_index(_head_index + 1)

#--- visualization core ---

func _get_slot_local_position(slot: Control) -> Vector2: ##maps a slot into the pips overlay's local space so pips follow panel motion cleanly
	var slot_global_position: Vector2 = slot.get_global_transform_with_canvas().origin
	return pips_layer.get_global_transform_with_canvas().affine_inverse() * slot_global_position

func _set_head_index(new_index: int) -> void:
	#prevent scrolling past end
	if new_index >= _full_schedule.size():
		return

	var old_index = _head_index
	_head_index = new_index

	#1. determine the "target state" of the ui
	#we want pips for indices [head ... head+slot_count]
	var target_entries: Array[TimelineEntry] = []
	for i: int in range(slot_count):
		if _head_index + i < _full_schedule.size():
			target_entries.append(_full_schedule[_head_index + i])

	#2. smart diffing (reuse existing pips if possible)
	#we iterate the existing pips and see if they match any target id.
	#if yes -> move them to new slot.
	#if no -> fade them out.

	var new_active_pips: Array[TimelinePip] = []
	new_active_pips.resize(target_entries.size())

	var claimed_pips: Dictionary = {} #pip -> true

	#a. map existing pips to new slots
	for pip in _active_pips:
		var found_match: bool = false
		for i: int in range(target_entries.size()):
			if target_entries[i].id == pip.entry_id: #assume pip stores this id
				new_active_pips[i] = pip
				pip.move_to_slot(_slots[i], _get_slot_local_position(_slots[i])) #animate within the timeline's local space
				claimed_pips[pip] = true
				found_match = true
				break

		#b. kill pips that fell off the left side
		if not found_match:
			pip.fade_out_and_die()

	#c. spawn new pips for empty slots (appearing on right)
	for i: int in range(target_entries.size()):
		if new_active_pips[i] == null:
			var entry = target_entries[i]
			var pip = _spawn_pip(entry)

			#visual spawn logic:
			#if we just advanced, new items slide in from right.
			#if we jumped, maybe they just appear?
			#let's assume slide-in from right for consistency.
			var spawn_pos: Vector2 = _get_slot_local_position(_slots[slot_count - 1]) + Vector2(100, 0)

			#special case: if this is a huge jump (reset), just spawn in place
			if abs(new_index - old_index) > 1:
				spawn_pos = _get_slot_local_position(_slots[i])

			pip.position = spawn_pos
			pip.move_to_slot(_slots[i], _get_slot_local_position(_slots[i]))
			new_active_pips[i] = pip

	_active_pips = new_active_pips

func _spawn_pip(entry: TimelineEntry) -> TimelinePip:
	var pip = pip_scene.instantiate() as TimelinePip
	pips_layer.add_child(pip)
	pip.setup(entry)
	pip.entry_id = entry.id #crucial for diffing!
	return pip
