#extends Control
#class_name WaveTimeline
#
#@export var slot_count: int = 6 ## number of foreseeable waves
#@export var slot_container: HBoxContainer ## at runtime, empty controls are placed here to define layout
#@export var pips_layer: Control ## where pips are actually instantiated (should be Full Rect)
#@export var pip_scene: PackedScene
#
#class TimelineEntry: ##condensed state of each wave (see Phases.Wave)
	#var wave_number: int
	#var is_combat: bool
	#var subtype: int ## CombatVariant or DayEvent enum
#
#var _schedule: Array[TimelineEntry] = []
#var _active_pips: Array[TimelinePip] = []
#var _slots: Array[Control] = []
#
## tracks the last wave we generated data for, so we can generate infinite future
#var _last_generated_wave: int = 0
#
#func _ready() -> void:
	#await get_tree().process_frame #wait for slots to settle down
	## cache slots (The anchors)
	#for child in slot_container.get_children():
		#if child is Control:
			#_slots.append(child)
			## make slots invisible, they are just position markers
			#child.modulate.a = 0 
	#_advance_timeline()
	#
	#UI.start_wave.connect(func(_wave): _advance_timeline())
	#UI.day_event_ended.connect(_advance_timeline)
	## UI.show_building_ui.connect(_advance_timeline) TODO: listen for inter-day event switches
	#
	## initial build (after phases has determined schedule)
	#UI.update_wave_schedule.connect(func():
		#_last_generated_wave = Phases.current_wave_number
		#_refill_schedule_buffer()
		#_initialize_pips()
	#)
	#
#
	#UI.tutorial_manager.register_element(TutorialManager.Reference.WAVE_TIMELINE, self)
	#
## called when a new wave starts.
## shifts everything left, destroys the old current, spawns new future.
#func _advance_timeline() -> void:
	## ensure we have enough future data
	#_refill_schedule_buffer()
#
	#if _active_pips.is_empty():
		#_initialize_pips()
	#
	## remove the pip that just passed (Slot 0)
	#var old_pip: TimelinePip = _active_pips.pop_front()
	#old_pip.fade_out_and_die()
	#
	## remove the data entry associated with it
	#if not _schedule.is_empty():
		#_schedule.pop_front()
#
	## shift existing pips to their new slots
	#for i: int in range(_active_pips.size()):
		#var pip = _active_pips[i]
		#if i < _slots.size():
			#pip.move_to_slot(_slots[i])
		#else:
			## if we have overflow pips, keep them waiting off-screen or hide them
			#pip.visible = false
#
	## spawn the new pip at the end (if needed to fill the view)
	## we currently have active_pips.size() items and want slot_count items
	#while _active_pips.size() < slot_count and _active_pips.size() < _schedule.size():
		#var new_data_index = _active_pips.size() # The index in the schedule
		#var slot_index = _active_pips.size() # The slot it goes to
		#
		#var entry: TimelineEntry = _schedule[new_data_index]
		#var new_pip: TimelinePip = _spawn_pip(entry)
		#
		## start at last slot + offset to slide in
		## TODO: dynamically calculate this offset
		#var spawn_pos: Vector2 = _slots[slot_count - 1].global_position + Vector2(100, 0)
		#new_pip.global_position = spawn_pos
		#
		## tell it to move to its designated slot
		#new_pip.move_to_slot(_slots[slot_index])
		#_active_pips.append(new_pip)
#
## data management
#func _refill_schedule_buffer() -> void: ## converts the PhaseManager's wave_plan into a flat list of Day->Night->Day->Night
	## keep generating until we have enough entries to fill the UI + buffer (2)
	#while _schedule.size() < slot_count + 2:
		#var wave: Phases.Wave = Phases.wave_plan.get(_last_generated_wave, null)
		#
		#if _last_generated_wave > Phases.FINAL_WAVE:
			#break
		#
		#if not wave:
			## if looking too far into future (beyond FINAL_WAVE), assume normal
			#wave = Phases.Wave.new() 
		#
		## add day events
		#for day_event: Phases.DayEvent in wave.day_events:
			#var entry := TimelineEntry.new()
			#entry.wave_number = _last_generated_wave
			#entry.is_combat = false
			#entry.subtype = day_event
			#_schedule.append(entry)
			#
		## add combat events (there can only be one per wave)
		#var combat_entry := TimelineEntry.new()
		#combat_entry.wave_number = _last_generated_wave
		#combat_entry.is_combat = true
		#combat_entry.subtype = wave.combat_variant
		#_schedule.append(combat_entry)
		#
		#_last_generated_wave += 1
#
#func _initialize_pips() -> void:
	## clear garbage
	#for child in pips_layer.get_children():
		#child.free()
	#_active_pips.clear()
#
	## ccreate initial set directly in position (no slide in animation for startup)
	#for i: int in range(min(slot_count, _schedule.size())):
		#var entry = _schedule[i]
		#var pip := _spawn_pip(entry)
		#pip.global_position = _slots[i].global_position
		#pip.target_slot = _slots[i]
		#_active_pips.append(pip)
#
#func _spawn_pip(entry: TimelineEntry) -> TimelinePip:
	#var pip := pip_scene.instantiate() as TimelinePip
	#pips_layer.add_child(pip)
	#pip.setup(entry)
	#return pip

extends Control
class_name WaveTimeline

# --- Config ---
@export var slot_count: int = 6
@export var slot_container: HBoxContainer 
@export var pips_layer: Control 
@export var pip_scene: PackedScene

# --- State ---
class TimelineEntry:
	var id: String # Unique ID for diffing (e.g. "Wave5_Event0")
	var wave_number: int
	var is_combat: bool
	var subtype: int

var _full_schedule: Array[TimelineEntry] = []
var _active_pips: Array[TimelinePip] = []
var _slots: Array[Control] = []

# Tracks the current "Head" of the timeline (what is in Slot 0)
var _head_index: int = 0

func _ready() -> void:
	await get_tree().process_frame
	for child in slot_container.get_children():
		if child is Control:
			_slots.append(child)
			#child.modulate.a = 0 
	
	_rebuild_full_schedule()
	# Connect Signals
	UI.start_wave.connect(func(wave): _jump_to_wave(wave, false))
	UI.start_phase.connect(func(wave, combat, subtype): _jump_to_wave(wave, combat, subtype))
	UI.update_wave_schedule.connect(_rebuild_full_schedule)
	
	UI.tutorial_manager.register_element(TutorialStep.Reference.WAVE_TIMELINE, self)

# --- Data Generation ---

func _rebuild_full_schedule() -> void:
	_full_schedule.clear()
	
	# Flatten the entire game plan into a linear list
	# This makes "Goto" logic trivial (just finding an index)
	for i: int in range(1, Phases.FINAL_WAVE + 1):
		var wave_data = Phases.wave_plan.get(i)
		if not wave_data: continue
		
		# A. Day Events
		for j: int in range(wave_data.day_events.size()):
			var entry = TimelineEntry.new()
			entry.wave_number = i
			entry.is_combat = false
			entry.subtype = wave_data.day_events[j]
			entry.id = "W%d_D%d" % [i, j]
			_full_schedule.append(entry)
			
		# B. Combat
		var entry = TimelineEntry.new()
		entry.wave_number = i
		entry.is_combat = true
		entry.subtype = wave_data.combat_variant
		entry.id = "W%d_C" % i
		_full_schedule.append(entry)
		
	# Initial Sync
	_jump_to_wave(Phases.current_wave_number, false)

# --- Navigation API ---

func _jump_to_wave(wave_number: int, is_combat_start: bool, subtype: int = -1) -> void:
	# Find the index in the flattened schedule
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
	
	if target_index == -1: return # Not found
	
	_set_head_index(target_index)

func _advance_one_step() -> void:
	_set_head_index(_head_index + 1)

# --- Visualization Core ---

func _set_head_index(new_index: int) -> void:
	# Prevent scrolling past end
	if new_index >= _full_schedule.size():
		return
		
	var old_index = _head_index
	_head_index = new_index
	
	# 1. Determine the "Target State" of the UI
	# We want Pips for indices [head ... head+slot_count]
	var target_entries: Array[TimelineEntry] = []
	for i: int in range(slot_count):
		if _head_index + i < _full_schedule.size():
			target_entries.append(_full_schedule[_head_index + i])

	# 2. Smart Diffing (Reuse existing pips if possible)
	# We iterate the existing pips and see if they match any target ID.
	# If yes -> Move them to new slot.
	# If no -> Fade them out.
	
	var new_active_pips: Array[TimelinePip] = []
	new_active_pips.resize(target_entries.size())
	
	var claimed_pips: Dictionary = {} # Pip -> True
	
	# A. Map existing pips to new slots
	for pip in _active_pips:
		var found_match = false
		for i: int in range(target_entries.size()):
			if target_entries[i].id == pip.entry_id: # Assume Pip stores this ID
				new_active_pips[i] = pip
				pip.move_to_slot(_slots[i]) # Animate to new position
				claimed_pips[pip] = true
				found_match = true
				break
		
		# B. Kill pips that fell off the left side
		if not found_match:
			pip.fade_out_and_die()

	# C. Spawn new pips for empty slots (appearing on right)
	for i: int in range(target_entries.size()):
		if new_active_pips[i] == null:
			var entry = target_entries[i]
			var pip = _spawn_pip(entry)
			
			# Visual spawn logic:
			# If we just advanced, new items slide in from right.
			# If we jumped, maybe they just appear? 
			# Let's assume slide-in from right for consistency.
			var spawn_pos = _slots[slot_count - 1].global_position + Vector2(100, 0)
			
			# Special case: If this is a huge jump (reset), just spawn in place
			if abs(new_index - old_index) > 1:
				spawn_pos = _slots[i].global_position
				
			pip.global_position = spawn_pos
			pip.move_to_slot(_slots[i])
			new_active_pips[i] = pip
			
	_active_pips = new_active_pips

func _spawn_pip(entry: TimelineEntry) -> TimelinePip:
	var pip = pip_scene.instantiate() as TimelinePip
	pips_layer.add_child(pip)
	pip.setup(entry)
	pip.entry_id = entry.id # Crucial for diffing!
	return pip
