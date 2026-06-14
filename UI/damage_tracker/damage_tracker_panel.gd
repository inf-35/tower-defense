extends Control
class_name DamageTrackerPanel

@export var rows_container: VBoxContainer
@export var row_scene: PackedScene

var _rows_by_entry_id: Dictionary[String, DamageTrackerRow] = {}
var _dirty: bool = false
var _pending_entries: Array[Dictionary] = []
var _pending_max_damage: float = 0.0

func _ready() -> void:
	set_process(false)
	UI.update_damage_tracker.connect(_on_damage_tracker_updated)
	UI.reset_damage_tracker.connect(_on_wave_started_reset)
	if Run.has_active_run() and is_instance_valid(Run.damage_tracker) and Run.damage_tracker.has_entries():
		_on_damage_tracker_updated(Run.damage_tracker.get_sorted_entries(), Run.damage_tracker.get_max_damage())

func _mark_dirty() -> void: ##coalesces heavy combat updates to one ui refresh per frame
	if _dirty:
		return
	_dirty = true
	set_process(true)

func _process(_delta: float) -> void:
	if not _dirty:
		set_process(false)
		return

	_refresh_rows()
	_dirty = false
	set_process(false)

func _refresh_rows() -> void: ##rebuilds ordering in place while reusing stable row instances
	for index: int in range(_pending_entries.size()):
		var entry: Dictionary = _pending_entries[index]
		var entry_id: String = str(entry["entry_id"])
		var row: DamageTrackerRow = _rows_by_entry_id.get(entry_id)
		if not is_instance_valid(row):
			row = row_scene.instantiate() as DamageTrackerRow
			row.pressed.connect(_on_row_pressed)
			_rows_by_entry_id[entry_id] = row
			rows_container.add_child(row)

		row.display_entry(entry, _pending_max_damage)
		rows_container.move_child(row, index)

func _on_wave_started_reset(_wave_number: int) -> void: ##clears all persisted rows when a new combat wave actually starts
	_pending_entries.clear()
	_pending_max_damage = 0.0
	for row: DamageTrackerRow in _rows_by_entry_id.values():
		if is_instance_valid(row):
			row.queue_free()
	_rows_by_entry_id.clear()

func _on_damage_tracker_updated(entries: Array[Dictionary], max_damage: float) -> void:
	_pending_entries = entries
	_pending_max_damage = max_damage
	_mark_dirty()

func _on_row_pressed(entry_id: String) -> void:
	if not Run.has_active_run() or not is_instance_valid(Run.damage_tracker):
		return

	var target: Unit = Run.damage_tracker.get_entry_target(entry_id)
	if not is_instance_valid(target):
		return
	Run.references.camera.focus_and_inspect_unit(target)
