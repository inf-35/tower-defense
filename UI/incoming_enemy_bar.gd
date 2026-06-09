extends VBoxContainer
class_name IncomingEnemyBar

@export var icon_size: Vector2 = Vector2(42, 42)

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
	for child: Node in get_children():
		child.queue_free()

	if not Run.is_run_ready() or Units.unit_stats.is_empty():
		_set_display_visible(false)
		if not Run.references_ready.is_connected(_refresh):
			Run.references_ready.connect(_refresh, CONNECT_ONE_SHOT)
		return

	var entries: Array[Dictionary] = _get_sorted_wave_entries(_current_wave)
	_set_display_visible(not entries.is_empty())
	for entry: Dictionary in entries:
		_create_icon(entry)

func _get_sorted_wave_entries(wave: int) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var wave_stacks: Array[Array] = WaveEnemies.get_enemies_for_wave(wave)
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

func _create_icon(entry: Dictionary) -> void:
	var type: Units.Type = entry.type
	var icon := TextureRect.new()
	icon.texture = Units.get_unit_icon(type)
	icon.custom_minimum_size = icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.mouse_entered.connect(_on_icon_hovered.bind(icon, entry))
	icon.mouse_exited.connect(_on_icon_unhovered.bind(icon))
	add_child(icon)

func _on_icon_hovered(icon: Control, entry: Dictionary) -> void:
	var type: Units.Type = entry.type
	var tooltip_data := KeywordService.get_keyword_data("U_%s" % Units.Type.keys()[type])
	tooltip_data = tooltip_data.duplicate(true)
	tooltip_data["description"] = "%d incoming%s" % [
		int(entry.count),
		"\nNew enemy type." if bool(entry.unseen) else ""
	]

	var tooltip_instance: TooltipPanel = KeywordService.TOOLTIP_PANEL.instantiate()
	add_child(tooltip_instance)
	tooltip_instance.show_tooltip(tooltip_data)
	icon.set_meta("active_tooltip", tooltip_instance)

func _on_icon_unhovered(icon: Control) -> void:
	if not icon.has_meta("active_tooltip"):
		return

	var tooltip_instance: TooltipPanel = icon.get_meta("active_tooltip")
	if is_instance_valid(tooltip_instance):
		tooltip_instance.on_link_mouse_exited()
	icon.remove_meta("active_tooltip")
