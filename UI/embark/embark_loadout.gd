extends Control
class_name EmbarkLoadout

@export var guild: GuildData: ##starting package displayed here; changing it rebuilds presentation without creating or modifying a player
	set(value):
		if guild == value:
			return
		guild = value
		if is_node_ready():
			refresh_loadout()
@export var loadout_hbox: HBoxContainer ##authored row receiving relic cards first, then structure cards in package order
@export var loadout_scroll: ScrollContainer ##horizontal viewport whose movement dismisses the active tooltip
@export var loadout_card_scene: PackedScene ##shared index-slot scene, including its title and attribute papers
@export var tooltip_host: Control ##unclipped ancestor that owns keyword tooltips outside the loadout viewport

var _active_tooltip: TooltipPanel
var _active_slot: IndexSlot

func _ready() -> void:
	loadout_scroll.get_h_scroll_bar().value_changed.connect(_on_scroll_changed)
	visibility_changed.connect(_on_visibility_changed)
	refresh_loadout()

func _exit_tree() -> void:
	_close_active_tooltip()

func refresh_loadout() -> void: ##reads the selected package and canonical definitions directly, without catalog visibility filtering or gameplay grants
	if guild != null and Run.has_active_run() and not Run.is_run_ready():
		return
	_close_active_tooltip()
	for child: Node in loadout_hbox.get_children():
		loadout_hbox.remove_child(child)
		child.queue_free()
	loadout_scroll.scroll_horizontal = 0
	if guild == null:
		return

	for relic: RelicData in guild.starting_relics:
		if relic == null:
			push_warning("EmbarkLoadout: guild '%s' contains an empty relic entry" % guild.title)
			continue
		_add_slot("R_%d" % int(relic.type), relic.icon, relic.title)

	for tower_type: Towers.Type in guild.starting_buildings:
		var tower_data: TowerData = Towers.tower_stats.get(tower_type) as TowerData
		if tower_data == null:
			push_warning("EmbarkLoadout: guild '%s' references unknown structure %d" % [guild.title, int(tower_type)])
			continue
		var prototype: Tower = Towers.get_tower_prototype(tower_type)
		var type_label: String = "Tower"
		if prototype.hostile:
			type_label = "Enemy"
		elif tower_data.is_rite:
			type_label = "Rite"
		elif tower_data.is_environmental or prototype.environmental:
			type_label = "Environment"
		var attributes: Array[IndexSlot.Attribute] = [
			IndexSlot.Attribute.new(&"type", "Type", type_label),
			IndexSlot.Attribute.new(&"size", "Size", "%dx%d" % [tower_data.size.x, tower_data.size.y]),
		]
		_add_slot("T_%s" % Towers.Type.keys()[tower_type], tower_data.icon, tower_data.tower_name, attributes)

func _add_slot(keyword: String, icon: Texture2D, title: String, attributes: Array[IndexSlot.Attribute] = []) -> void: ##wraps each configured slot in motion while leaving its own tooltip signals intact
	var slot: IndexSlot = loadout_card_scene.instantiate() as IndexSlot
	slot.configure(keyword, icon, title, attributes)
	var motion: AnimatableUI = AnimatableUI.new()
	motion.content = slot
	motion.hover_enabled = false
	motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motion.custom_minimum_size = slot.get_combined_minimum_size()
	slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.minimum_size_changed.connect(_sync_motion_minimum_size.bind(slot, motion))
	slot.hover_started.connect(_on_slot_hover_started.bind(slot, motion))
	slot.hover_ended.connect(_on_slot_hover_ended.bind(slot, motion))
	motion.add_child(slot)
	loadout_hbox.add_child(motion)

func _sync_motion_minimum_size(slot: IndexSlot, motion: AnimatableUI) -> void: ##keeps row allocation aligned with the slot's live attribute-paper overhang
	if not is_instance_valid(slot) or not is_instance_valid(motion):
		return
	motion.custom_minimum_size = slot.get_combined_minimum_size()

func _on_slot_hover_started(keyword: String, slot: IndexSlot, motion: AnimatableUI) -> void: ##expands the card and opens the standard keyword panel outside scrolling clips
	motion.set_hover_active(true)
	motion.z_index = 1
	if not is_visible_in_tree() or (Run.has_active_run() and not Run.is_run_ready()):
		return
	_close_active_tooltip()
	var tooltip_data: Dictionary = KeywordService.get_keyword_data(keyword)
	if tooltip_data.is_empty():
		return
	_active_slot = slot
	_active_tooltip = KeywordService.TOOLTIP_PANEL.instantiate() as TooltipPanel
	tooltip_host.add_child(_active_tooltip)
	_active_tooltip.show_tooltip(tooltip_data)

func _on_slot_hover_ended(slot: IndexSlot, motion: AnimatableUI) -> void:
	motion.set_hover_active(false)
	motion.z_index = 0
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

func _close_active_tooltip() -> void: ##also closes nested tooltips when the package changes, the row hides, or this view leaves the tree
	if is_instance_valid(_active_tooltip):
		_active_tooltip.close()
	_active_tooltip = null
	_active_slot = null
