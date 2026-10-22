extends Control
class_name IndexPage

enum Category {
	STRUCTURES,
	RELICS,
	ENEMIES,
}

enum StructureOrder {
	ALLIED_NORMAL,
	RITE,
	ENVIRONMENTAL,
	HOSTILE,
}

@export var structures_tab: Button ##tab that lists allied structures, rites, environmental structures, and hostiles
@export var relics_tab: Button ##tab that lists authored relics
@export var enemies_tab: Button ##tab that lists registered unit types
@export var scroll_container: ScrollContainer ##scroll view whose movement closes the active tooltip
@export var entry_grid: GridContainer ##native six-column grid that owns generated slots
@export var index_slot_scene: PackedScene ##slot scene used for each registry entry
@export var tooltip_host: Control ##unclipped control that owns screen-space keyword tooltips

var _current_category: Category = Category.STRUCTURES
var _active_tooltip: TooltipPanel
var _active_slot: IndexSlot
var _connected_player: Player
var _is_run_ending: bool = false

func _ready() -> void:
	structures_tab.pressed.connect(_on_category_selected.bind(Category.STRUCTURES))
	relics_tab.pressed.connect(_on_category_selected.bind(Category.RELICS))
	enemies_tab.pressed.connect(_on_category_selected.bind(Category.ENEMIES))
	scroll_container.get_v_scroll_bar().value_changed.connect(_on_scroll_changed)
	scroll_container.get_h_scroll_bar().value_changed.connect(_on_scroll_changed)
	visibility_changed.connect(_on_visibility_changed)
	Run.references_ready.connect(_on_references_ready)
	Run.run_ending.connect(_on_run_ending)
	if Run.is_run_ready():
		_on_references_ready()
	else:
		_refresh_entries()

func _exit_tree() -> void:
	_close_active_tooltip()
	_disconnect_player_relic_signal()

func _on_category_selected(category: Category) -> void:
	_close_active_tooltip()
	_current_category = category
	_refresh_entries()
	scroll_container.scroll_vertical = 0

func _refresh_entries() -> void: ##rebuilds the selected category from authored registries only when run prototypes are safe to query
	if _is_run_ending or (Run.has_active_run() and not Run.is_run_ready()):
		return

	var entries: Array[Dictionary] = []
	match _current_category:
		Category.STRUCTURES:
			entries = _build_structure_entries()
		Category.RELICS:
			entries = _build_relic_entries()
		Category.ENEMIES:
			entries = _build_enemy_entries()

	_clear_grid()
	for entry: Dictionary in entries:
		var slot: IndexSlot = index_slot_scene.instantiate() as IndexSlot
		var attributes: Array[IndexSlot.Attribute] = entry["attributes"]
		slot.configure(String(entry["keyword"]), entry["icon"] as Texture2D, String(entry["name"]), attributes)
		slot.hover_started.connect(_on_slot_hover_started.bind(slot))
		slot.hover_ended.connect(_on_slot_hover_ended.bind(slot))
		entry_grid.add_child(slot)

func _build_structure_entries() -> Array[Dictionary]: ##groups towers by affiliation and authored structure role before sorting within each group
	var entries: Array[Dictionary] = []
	for tower_type: Towers.Type in Towers.tower_stats:
		var tower_data: TowerData = Towers.tower_stats[tower_type]
		if not tower_data.indexable:
			continue
		var prototype: Tower = Towers.get_tower_prototype(tower_type)
		var order: StructureOrder = StructureOrder.ALLIED_NORMAL
		if prototype.hostile:
			order = StructureOrder.HOSTILE
		elif tower_data.is_rite:
			order = StructureOrder.RITE
		elif tower_data.is_environmental or prototype.environmental:
			order = StructureOrder.ENVIRONMENTAL

		var type_label: String = "Tower"
		match order:
			StructureOrder.RITE:
				type_label = "Rite"
			StructureOrder.ENVIRONMENTAL:
				type_label = "Environment"
			StructureOrder.HOSTILE:
				type_label = "Enemy"
		var attributes: Array[IndexSlot.Attribute] = [
			IndexSlot.Attribute.new(&"type", "Type", type_label),
			IndexSlot.Attribute.new(&"size", "Size", "%dx%d" % [tower_data.size.x, tower_data.size.y]),
		]

		entries.append(_make_entry(
			tower_data.tower_name,
			int(tower_type),
			"T_%s" % Towers.Type.keys()[tower_type],
			tower_data.icon,
			int(order),
			attributes
		))

	entries.sort_custom(_entry_precedes)
	return entries

func _build_relic_entries() -> Array[Dictionary]: ##builds relic entries from the registered relic resources
	var entries: Array[Dictionary] = []
	Relics.ensure_loaded()
	for relic_type: RelicData.Type in Relics.relics:
		var relic: RelicData = Relics.relics[relic_type]
		if not relic.indexable:
			continue
		entries.append(_make_entry(relic.title, int(relic_type), "R_%d" % int(relic_type), relic.icon))

	entries.sort_custom(_entry_precedes)
	return entries

func _build_enemy_entries() -> Array[Dictionary]: ##builds enemy entries from unit data without calculating prototype stats
	var entries: Array[Dictionary] = []
	for unit_type: Units.Type in Units.unit_stats:
		var unit_data: UnitData = Units.unit_stats[unit_type]
		if not unit_data.indexable:
			continue
		entries.append(_make_entry(
			unit_data.title,
			int(unit_type),
			"U_%s" % Units.Type.keys()[unit_type],
			unit_data.icon
		))

	entries.sort_custom(_entry_precedes)
	return entries

func _make_entry(entry_name: String, entry_id: int, keyword: String, icon: Texture2D, order: int = 0, attributes: Array[IndexSlot.Attribute] = []) -> Dictionary: ##keeps generic presentation attributes beside the canonical registry key
	return {
		"name": entry_name,
		"id": entry_id,
		"keyword": keyword,
		"icon": icon,
		"order": order,
		"attributes": attributes,
	}

func _entry_precedes(first: Dictionary, second: Dictionary) -> bool: ##orders entries by group, case-insensitive name, and registry id
	var first_order: int = int(first["order"])
	var second_order: int = int(second["order"])
	if first_order != second_order:
		return first_order < second_order

	var first_name: String = String(first["name"]).to_lower()
	var second_name: String = String(second["name"]).to_lower()
	if first_name != second_name:
		return first_name < second_name
	return int(first["id"]) < int(second["id"])

func _clear_grid() -> void:
	for child: Node in entry_grid.get_children():
		entry_grid.remove_child(child)
		child.queue_free()

func _on_slot_hover_started(keyword: String, slot: IndexSlot) -> void: ##opens the standard keyword tooltip on demand outside the clipped scroll view
	if _is_run_ending or (Run.has_active_run() and not Run.is_run_ready()) or not is_visible_in_tree():
		return
	_close_active_tooltip()
	var tooltip_data: Dictionary = KeywordService.get_keyword_data(keyword)
	if tooltip_data.is_empty():
		return

	_active_slot = slot
	_active_tooltip = KeywordService.TOOLTIP_PANEL.instantiate() as TooltipPanel
	tooltip_host.add_child(_active_tooltip)
	_active_tooltip.show_tooltip(tooltip_data)

func _on_slot_hover_ended(slot: IndexSlot) -> void:
	if _active_slot != slot:
		return
	if is_instance_valid(_active_tooltip):
		_active_tooltip.on_link_mouse_exited()
	_active_slot = null

func _on_scroll_changed(_value: float) -> void:
	_close_active_tooltip()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_close_active_tooltip()
		return
	_refresh_entries()

func _on_references_ready() -> void:
	_is_run_ending = false
	_close_active_tooltip()
	_disconnect_player_relic_signal()
	_connected_player = Run.player
	if is_instance_valid(_connected_player):
		_connected_player.relics_changed.connect(_on_relics_changed)
	_refresh_entries()

func _on_run_ending() -> void:
	_is_run_ending = true
	_close_active_tooltip()
	_disconnect_player_relic_signal()
	call_deferred("_refresh_after_run_ending")

func _refresh_after_run_ending() -> void:
	if Run.has_active_run():
		return
	_is_run_ending = false
	_refresh_entries()

func _on_relics_changed() -> void:
	_close_active_tooltip()

func _disconnect_player_relic_signal() -> void:
	if is_instance_valid(_connected_player) and _connected_player.relics_changed.is_connected(_on_relics_changed):
		_connected_player.relics_changed.disconnect(_on_relics_changed)
	_connected_player = null

func _close_active_tooltip() -> void:
	if is_instance_valid(_active_tooltip):
		_active_tooltip.close()
	_active_tooltip = null
	_active_slot = null
