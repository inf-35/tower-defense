extends GridContainer
class_name RelicDisplay

enum DisplayMode {
	PLAYER_RELICS,
	MANUAL,
}

const RELIC_SLOT_SCENE: PackedScene = preload("res://UI/relic_display/relic_slot.tscn")
const RELIC_PURCHASE_BUTTON_SCENE: PackedScene = preload("res://UI/relic_display/relic_purchase_button.tscn")
const DELETE_TOOLTIP_HINT: String = "RMB: destroy relic"

#--- configuration ---
@export var icon_size: Vector2 = Vector2(70, 70)
@export var icon_stretch_mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
@export var display_mode: DisplayMode = DisplayMode.PLAYER_RELICS
@export var debug_hover_icons: bool = false
@export var slot_frame_offset: Vector2 = Vector2.ZERO ##offsets the drawn slot art relative to the relic icon so the box can be nudged without moving the icon itself
@export var relic_icon_inset: float = 6.0 ##uniform padding keeping relic art comfortably inside its slot frame

var _manual_entries: Array[Dictionary] = []
var _last_hovered_control_path: String = ""

func _ready() -> void:
	if not Run.is_run_ready():
		await Run.references_ready
	if display_mode == DisplayMode.PLAYER_RELICS:
		UI.update_relics.connect(_refresh_display)
		UI.update_flux.connect(_on_flux_changed)
	set_process(debug_hover_icons)

	#initial population
	_refresh_display()
	_debug_log("ready, mode=%s, children=%d" % [DisplayMode.keys()[display_mode], get_child_count()])

func _process(_delta: float) -> void:
	if not debug_hover_icons or not visible:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hovered_path: String = "<none>"
	if is_instance_valid(hovered):
		hovered_path = str(hovered.get_path())
	if hovered_path != _last_hovered_control_path:
		_last_hovered_control_path = hovered_path
		_debug_log("viewport hovered control = %s" % hovered_path)

func _refresh_display() -> void:
	for child in get_children():
		child.queue_free()

	if display_mode == DisplayMode.PLAYER_RELICS:
		_create_player_relic_slots()
		return

	var entries: Array[Dictionary] = _manual_entries
	_debug_log("refreshing %d entries" % entries.size())
	for entry: Dictionary in entries:
		_create_icon(entry)

func show_relics(relics: Array[RelicData]) -> void:
	var entries: Array[Dictionary] = []
	for relic: RelicData in relics:
		entries.append(_build_relic_entry(relic))
	show_entries(entries)

func show_towers(types: Array[Towers.Type]) -> void:
	var entries: Array[Dictionary] = []
	for tower_type: Towers.Type in types:
		entries.append(_build_tower_entry(tower_type))
	show_entries(entries)

func show_entries(entries: Array[Dictionary]) -> void:
	display_mode = DisplayMode.MANUAL
	_manual_entries = entries.duplicate(true)
	if is_node_ready():
		_refresh_display()

func _create_player_relic_slots() -> void: ##rebuilds the live relic bar as framed occupied slots, empty slots, and the trailing purchase button
	var relic_entries: Array[Dictionary] = []
	for relic: RelicData in Run.player.active_relics:
		var entry: Dictionary = _build_relic_entry(relic)
		var tooltip_data: Dictionary = entry.get("tooltip_data", {}).duplicate(true)
		var description: String = String(tooltip_data.get("description", ""))
		var delete_hint: String = KeywordService.wrap_text(DELETE_TOOLTIP_HINT, "bad")
		if description.is_empty():
			tooltip_data["description"] = delete_hint
		else:
			tooltip_data["description"] = "%s\n%s" % [description, delete_hint]
		entry["tooltip_data"] = tooltip_data
		relic_entries.append(entry)

	for entry: Dictionary in relic_entries:
		_create_slotted_icon(entry)

	for _index: int in range(maxi(Run.player.relic_slot_capacity - relic_entries.size(), 0)):
		_create_empty_slot()

	_create_purchase_slot_button()

func _build_relic_entry(relic: RelicData) -> Dictionary:
	var tooltip_data := KeywordService.get_keyword_data("R_%d" % relic.type)
	return {
		"relic": relic,
		"icon": tooltip_data.get("icon", relic.icon),
		"tooltip_data": tooltip_data,
	}

func _build_tower_entry(tower_type: Towers.Type) -> Dictionary:
	var tooltip_data := KeywordService.get_keyword_data("T_%s" % Towers.Type.keys()[tower_type])
	if Towers.is_tower_rite(tower_type) and not tooltip_data.is_empty():
		tooltip_data = tooltip_data.duplicate(true)
		tooltip_data["labels"] = str(tooltip_data.get("labels", "")) + "[Rite]"
	return {
		"icon": tooltip_data.get("icon", Towers.get_tower_icon(tower_type)),
		"tooltip_data": tooltip_data,
	}

func _create_icon(entry: Dictionary) -> void:
	var icon_node: TextureRect = _build_icon_node(entry)

	#connect signals for tooltip logic
	icon_node.mouse_entered.connect(_on_icon_hovered.bind(icon_node, entry.get("tooltip_data", {})))
	icon_node.mouse_exited.connect(_on_icon_unhovered.bind(icon_node))
	icon_node.gui_input.connect(_on_icon_gui_input.bind(icon_node, entry))

	add_child(icon_node)
	var title: String = entry.get("tooltip_data", {}).get("title", "Unknown")
	_debug_log("created icon '%s'" % title)
	if debug_hover_icons:
		call_deferred("_log_icon_layout", icon_node, title)

func _create_slotted_icon(entry: Dictionary) -> void: ##wraps one relic icon in the slot frame so occupied slots visually sit inside the same slot grid as empties
	var cell := RELIC_SLOT_SCENE.instantiate() as RelicSlot
	cell.custom_minimum_size = icon_size
	cell.set_slot_offset(slot_frame_offset)
	cell.set_icon_inset(relic_icon_inset)
	cell.show_icon(entry.get("icon"))
	var icon_node: TextureRect = cell.get_icon_control()

	icon_node.mouse_entered.connect(_on_icon_hovered.bind(icon_node, entry.get("tooltip_data", {})))
	icon_node.mouse_exited.connect(_on_icon_unhovered.bind(icon_node))
	icon_node.gui_input.connect(_on_icon_gui_input.bind(icon_node, entry))

	add_child(cell)

func _create_empty_slot() -> void: ##creates a blank slot frame for unoccupied relic capacity
	var cell := RELIC_SLOT_SCENE.instantiate() as RelicSlot
	cell.custom_minimum_size = icon_size
	cell.set_slot_offset(slot_frame_offset)
	cell.set_icon_inset(relic_icon_inset)
	cell.show_empty()
	add_child(cell)

func _create_purchase_slot_button() -> void: ##adds the trailing purchase-slot scene so the icon and cost label stay owned by one grid child
	var cost: float = Run.player.get_next_relic_slot_cost()
	var affordable: bool = Run.player.flux >= cost
	var button := RELIC_PURCHASE_BUTTON_SCENE.instantiate() as RelicPurchaseButton
	button.configure(slot_frame_offset, affordable, cost)
	button.pressed.connect(_on_purchase_slot_pressed)
	add_child(button)

func _build_icon_node(entry: Dictionary) -> TextureRect: ##creates the icon node shared by manual relic/tower strips and slotted live relic entries
	var icon_node := TextureRect.new()
	icon_node.texture = entry.get("icon")
	icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_node.stretch_mode = icon_stretch_mode
	icon_node.custom_minimum_size = icon_size
	icon_node.mouse_filter = Control.MOUSE_FILTER_STOP
	return icon_node

func _on_purchase_slot_pressed() -> void:
	Run.player.try_purchase_relic_slot()

func _on_flux_changed(_flux: float) -> void:
	if display_mode != DisplayMode.PLAYER_RELICS:
		return
	_refresh_display()

#--- tooltip integration ---

func _on_icon_hovered(icon_node: Control, tooltip_data: Dictionary) -> void:
	_debug_log("hover enter '%s'" % tooltip_data.get("title", "Unknown"))
	#2. instantiate the standardized tooltip panel
	#we use the factory scene from keywordservice to ensure consistency s the game
	var tooltip_instance: TooltipPanel = KeywordService.TOOLTIP_PANEL.instantiate()

	#3. keep the old hosting path while we debug whether hover itself is firing.
	add_child(tooltip_instance)
	_debug_log("spawned tooltip on %s" % get_path())

	#4. display the data
	#this triggers the tooltippanel's internal 'solidify' timer logic automatically
	tooltip_instance.show_tooltip(tooltip_data)

	#5. store a reference to the active tooltip on the icon itself.
	#this allows us to retrieve and close the specific tooltip instance later.
	icon_node.set_meta("active_tooltip", tooltip_instance)

func _on_icon_unhovered(icon_node: Control) -> void:
	_debug_log("hover exit")
	#check if this icon currently owns an open tooltip
	if icon_node.has_meta("active_tooltip"):
		var tooltip_instance: TooltipPanel = icon_node.get_meta("active_tooltip")

		if is_instance_valid(tooltip_instance):
			#critical: we do not call queue_free() directly.
			#we call on_link_mouse_exited(), which triggers the "grace period" logic.
			#this allows the player to move their mouse from the icon into the tooltip
			#to read nested keywords, matching the behavior of your text links.
			tooltip_instance.on_link_mouse_exited()

		#clean up the reference on the icon, as the tooltip now manages its own lifecycle
		icon_node.remove_meta("active_tooltip")

func _on_icon_gui_input(event: InputEvent, icon_node: Control, entry: Dictionary) -> void:
	if display_mode == DisplayMode.PLAYER_RELICS and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var relic: RelicData = entry.get("relic", null) as RelicData
			if is_instance_valid(relic):
				Run.player.remove_relic(relic)
				if icon_node.has_meta("active_tooltip"):
					var tooltip_instance: TooltipPanel = icon_node.get_meta("active_tooltip")
					if is_instance_valid(tooltip_instance):
						tooltip_instance.close()
					icon_node.remove_meta("active_tooltip")
				get_viewport().set_input_as_handled()
				return

	if not debug_hover_icons:
		return
	var title: String = entry.get("tooltip_data", {}).get("title", "Unknown")
	if event is InputEventMouseMotion:
		_debug_log("gui_input motion on '%s'" % title)
	elif event is InputEventMouseButton:
		_debug_log("gui_input button %d pressed=%s on '%s'" % [event.button_index, str(event.pressed), title])

func _log_icon_layout(icon_node: Control, title: String) -> void:
	if not debug_hover_icons or not is_instance_valid(icon_node):
		return
	_debug_log(
		"icon layout '%s' pos=%s size=%s global=%s mouse_filter=%d" %
		[title, str(icon_node.position), str(icon_node.size), str(icon_node.global_position), icon_node.mouse_filter]
	)

func _debug_log(message: String) -> void:
	if debug_hover_icons:
		print("[RelicDisplay:%s] %s" % [name, message])
