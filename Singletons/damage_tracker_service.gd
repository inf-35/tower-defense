extends Node
class_name DamageTrackerService

const STATUS_DAMAGE_ATTRIBUTES: Array[Attributes.id] = [
	Attributes.id.REGENERATION,
	Attributes.id.REGEN_PERCENT,
	Attributes.id.REGEN_REMAINDER_PERCENT,
]

var _tower_entries_by_unit_id: Dictionary[int, Dictionary] = {}
var _tower_refs_by_unit_id: Dictionary[int, WeakRef] = {}
var _status_entries_by_key: Dictionary[String, Dictionary] = {}
var _sorted_entries: Array[Dictionary] = []
var _first_seen_counter: int = 0
var _max_damage: float = 0.0
var _dirty: bool = false

func _ready() -> void:
	set_process(false)
	Run.player.on_event.connect(_on_player_event)
	Run.waves.wave_started.connect(_on_wave_started)

func has_entries() -> bool: ##returns whether the current cached ranking has at least one entry
	return not _sorted_entries.is_empty()

func get_sorted_entries() -> Array[Dictionary]: ##returns the current ranking snapshot sorted by damage desc and discovery order asc
	return _sorted_entries

func get_max_damage() -> float: ##returns the current leading damage value for ui normalization
	return _max_damage

func get_entry_target(entry_id: String) -> Unit: ##returns the currently live tower target for a tracker entry, if any
	if not entry_id.begins_with("tower:"):
		return null

	var unit_id: int = int(entry_id.trim_prefix("tower:"))
	if not _tower_refs_by_unit_id.has(unit_id):
		return null

	var weak_ref: WeakRef = _tower_refs_by_unit_id[unit_id]
	var target = weak_ref.get_ref() if is_instance_valid(weak_ref) else null
	return target as Unit if is_instance_valid(target) else null

func clear_for_wave(wave_number: int) -> void: ##drops all ranking state for the newly started combat wave
	_tower_entries_by_unit_id.clear()
	_tower_refs_by_unit_id.clear()
	_status_entries_by_key.clear()
	_sorted_entries.clear()
	_first_seen_counter = 0
	_max_damage = 0.0
	_dirty = false
	set_process(false)
	UI.reset_damage_tracker.emit(wave_number)
	UI.update_damage_tracker.emit(_sorted_entries, _max_damage)

func _on_player_event(_unit: Unit, game_event: GameEvent) -> void: ##filters the global event stream down to final tower-attributed damage reports
	if Run.waves.current_combat_wave_number <= 0:
		return
	if game_event.event_type != GameEvent.EventType.HIT_DEALT:
		return
	if !(game_event.data is HitReportData):
		return

	var hit_report: HitReportData = game_event.data as HitReportData
	if !is_instance_valid(hit_report.source) or !(hit_report.source is Tower):
		return
	if !is_instance_valid(hit_report.target) or !hit_report.target.hostile:
		return
	if hit_report.damage_caused <= 0.0:
		return

	_record_damage(hit_report.source as Tower, hit_report.damage_caused)

func record_status_damage(status_type: Attributes.Status, damage_caused: float) -> void: ##records unattributed status damage into one aggregate row per status type
	if Run.waves.current_combat_wave_number <= 0:
		return
	if damage_caused <= 0.0:
		return

	var status_key: String = Attributes.Status.keys()[status_type]
	var entry_id: String = "status:%s" % status_key
	if not _status_entries_by_key.has(entry_id):
		var keyword_data: Dictionary = KeywordService.get_keyword_data(status_key)
		_status_entries_by_key[entry_id] = {
			"entry_id": entry_id,
			"unit_id": -1,
			"tower_type": Towers.Type.VOID,
			"status_type": status_type,
			"tower_name": str(keyword_data.get("title", status_key.capitalize())),
			"damage_total": 0.0,
			"first_seen_order": _first_seen_counter,
			"is_focusable": false,
		}
		_first_seen_counter += 1

	var entry: Dictionary = _status_entries_by_key[entry_id]
	entry["damage_total"] = float(entry["damage_total"]) + damage_caused
	_status_entries_by_key[entry_id] = entry

	if not _dirty:
		_dirty = true
		set_process(true)

func _record_damage(source_tower: Tower, damage_caused: float) -> void: ##captures one resolved damage report against the owning tower row
	var unit_id: int = source_tower.unit_id
	var entry_id: String = "tower:%s" % str(unit_id)
	if not _tower_entries_by_unit_id.has(unit_id):
		_tower_entries_by_unit_id[unit_id] = {
			"entry_id": entry_id,
			"unit_id": unit_id,
			"tower_type": source_tower.type,
			"status_type": -1,
			"tower_name": Towers.get_tower_name(source_tower.type),
			"damage_total": 0.0,
			"first_seen_order": _first_seen_counter,
			"is_focusable": true,
		}
		_first_seen_counter += 1

	_tower_refs_by_unit_id[unit_id] = weakref(source_tower)
	var entry: Dictionary = _tower_entries_by_unit_id[unit_id]
	entry["damage_total"] = float(entry["damage_total"]) + damage_caused
	_tower_entries_by_unit_id[unit_id] = entry

	if not _dirty:
		_dirty = true
		set_process(true)

func _process(_delta: float) -> void: ##coalesces ranking recomputation to once per frame under heavy combat
	if not _dirty:
		set_process(false)
		return

	_rebuild_sorted_entries()
	_dirty = false
	set_process(false)
	UI.update_damage_tracker.emit(_sorted_entries, _max_damage)

func _rebuild_sorted_entries() -> void: ##rebuilds the cached sorted snapshot consumed by the hud
	_sorted_entries.clear()
	_max_damage = 0.0

	for entry: Dictionary in _tower_entries_by_unit_id.values():
		_sorted_entries.append(entry)
		_max_damage = maxf(_max_damage, float(entry["damage_total"]))

	for entry: Dictionary in _status_entries_by_key.values():
		_sorted_entries.append(entry)
		_max_damage = maxf(_max_damage, float(entry["damage_total"]))

	_sorted_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var damage_a: float = float(a["damage_total"])
		var damage_b: float = float(b["damage_total"])
		if not is_equal_approx(damage_a, damage_b):
			return damage_a > damage_b
		return int(a["first_seen_order"]) < int(b["first_seen_order"])
	)

func _on_wave_started(wave_number: int) -> void:
	clear_for_wave(wave_number)
