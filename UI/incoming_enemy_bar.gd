extends Control
class_name IncomingEnemyBar

@export var roster_label: InteractiveRichTextLabel

var _current_wave: int = 1

func _ready() -> void:
	UI.start_wave.connect(_on_wave_changed)
	UI.start_phase.connect(func(wave: int, _combat: bool, _subtype: int) -> void:
		_on_wave_changed(wave)
	)
	UI.update_wave_schedule.connect(_refresh)
	_refresh()

func _on_wave_changed(wave: int) -> void:
	_current_wave = maxi(wave, 1)
	_refresh()

func _refresh() -> void:
	if not Run.is_run_ready() or Units.unit_stats.is_empty():
		_set_display_visible(false)
		if not Run.references_ready.is_connected(_refresh):
			Run.references_ready.connect(_refresh, CONNECT_ONE_SHOT)
		return

	var entries: Array[Dictionary] = _get_sorted_wave_entries(_current_wave)
	_set_display_visible(not entries.is_empty())
	if entries.is_empty():
		return
	roster_label.set_parsed_text(_build_roster_text(entries))

func _get_sorted_wave_entries(wave: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var wave_stacks: Array[Array] = Run.waves.get_planned_enemies_for_wave(wave) if is_instance_valid(Run.waves) else WaveEnemies.get_enemies_for_wave(wave)
	var counts: Dictionary[Units.Type, int] = {}

	for stack: Array in wave_stacks:
		var type: Units.Type = stack[0]
		var count: int = int(stack[1])
		if count <= 0 or not Units.unit_stats.has(type):
			continue
		counts[type] = counts.get(type, 0) + count

	for type: Units.Type in counts:
		entries.append({
			"type": type,
			"count": counts[type],
			"unseen": _is_enemy_type_unseen(type, wave),
			"strength": Units.get_unit_strength(type),
		})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a.unseen) != bool(b.unseen):
			return bool(a.unseen)
		return float(a.strength) > float(b.strength)
	)
	return entries

func _is_enemy_type_unseen(type: Units.Type, wave: int) -> bool:
	for previous_wave: int in range(1, wave):
		for stack: Array in WaveEnemies.get_enemies_for_wave(previous_wave):
			if stack[0] == type:
				return false

	return true

func _set_display_visible(displayed: bool) -> void:
	visible = displayed
	var panel := get_parent().get_parent() as CanvasItem
	if is_instance_valid(panel):
		panel.visible = displayed

func _build_roster_text(entries: Array[Dictionary]) -> String: ##formats the next-wave preview into one compact keyword-aware roster line
	var chunks: Array[String] = []
	for entry: Dictionary in entries:
		var type: Units.Type = entry.type
		var chunk: String = "{U_%s} x %d" % [Units.Type.keys()[type], int(entry.count)]
		if bool(entry.unseen):
			chunk = KeywordService.wrap_text(chunk, "action")
		chunks.append(chunk)
	return "This wave:\n" + ", ".join(chunks)
