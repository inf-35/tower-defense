extends GridContainer
class_name RelicDisplay

enum DisplayMode {
	PLAYER_RELICS,
	MANUAL,
}

# --- configuration ---
@export var icon_size: Vector2 = Vector2(70, 70)
@export var icon_stretch_mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
@export var display_mode: DisplayMode = DisplayMode.PLAYER_RELICS
@export var debug_hover_icons: bool = false

var _manual_entries: Array[Dictionary] = []
var _last_hovered_control_path: String = ""

func _ready() -> void:
	if display_mode == DisplayMode.PLAYER_RELICS:
		UI.update_relics.connect(_refresh_display)
	
	#initial population
	_refresh_display()
	_debug_log("ready, mode=%s, children=%d" % [DisplayMode.keys()[display_mode], get_child_count()])

func _process(_delta: float) -> void:
	if not debug_hover_icons or not visible:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hovered_path := "<none>"
	if is_instance_valid(hovered):
		hovered_path = str(hovered.get_path())
	if hovered_path != _last_hovered_control_path:
		_last_hovered_control_path = hovered_path
		_debug_log("viewport hovered control = %s" % hovered_path)

func _refresh_display() -> void:
	for child in get_children():
		child.queue_free()

	var entries: Array[Dictionary] = _manual_entries if display_mode == DisplayMode.MANUAL else _build_player_relic_entries()
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

func _build_player_relic_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for relic: RelicData in Player.active_relics:
		entries.append(_build_relic_entry(relic))
	return entries

func _build_relic_entry(relic: RelicData) -> Dictionary:
	var tooltip_data := KeywordService.get_keyword_data("R_%d" % relic.type)
	return {
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
	# use a simple TextureRect for the visual representation
	var icon_node := TextureRect.new()
	icon_node.texture = entry.get("icon")
	
	# visual formatting
	icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_node.stretch_mode = icon_stretch_mode
	icon_node.custom_minimum_size = icon_size
	
	# enable mouse interaction so we can detect hovers
	icon_node.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# connect signals for tooltip logic
	icon_node.mouse_entered.connect(_on_icon_hovered.bind(icon_node, entry.get("tooltip_data", {})))
	icon_node.mouse_exited.connect(_on_icon_unhovered.bind(icon_node))
	icon_node.gui_input.connect(_on_icon_gui_input.bind(icon_node, entry.get("tooltip_data", {}).get("title", "Unknown")))
	
	add_child(icon_node)
	var title : String = entry.get("tooltip_data", {}).get("title", "Unknown")
	_debug_log("created icon '%s'" % title)
	if debug_hover_icons:
		call_deferred("_log_icon_layout", icon_node, title)

# --- Tooltip Integration ---

func _on_icon_hovered(icon_node: Control, tooltip_data: Dictionary) -> void:
	_debug_log("hover enter '%s'" % tooltip_data.get("title", "Unknown"))
	# 2. Instantiate the standardized tooltip panel
	# We use the factory scene from KeywordService to ensure consistency s the game
	var tooltip_instance: TooltipPanel = KeywordService.TOOLTIP_PANEL.instantiate()
	
	# 3. Keep the old hosting path while we debug whether hover itself is firing.
	add_child(tooltip_instance)
	_debug_log("spawned tooltip on %s" % get_path())
	
	# 4. Display the data
	# This triggers the TooltipPanel's internal 'solidify' timer logic automatically
	tooltip_instance.show_tooltip(tooltip_data)
	
	# 5. Store a reference to the active tooltip on the icon itself.
	# This allows us to retrieve and close the specific tooltip instance later.
	icon_node.set_meta("active_tooltip", tooltip_instance)

func _on_icon_unhovered(icon_node: Control) -> void:
	_debug_log("hover exit")
	# Check if this icon currently owns an open tooltip
	if icon_node.has_meta("active_tooltip"):
		var tooltip_instance: TooltipPanel = icon_node.get_meta("active_tooltip")
		
		if is_instance_valid(tooltip_instance):
			# CRITICAL: We do NOT call queue_free() directly.
			# We call on_link_mouse_exited(), which triggers the "Grace Period" logic.
			# This allows the player to move their mouse FROM the icon INTO the tooltip
			# to read nested keywords, matching the behavior of your text links.
			tooltip_instance.on_link_mouse_exited()
		
		# Clean up the reference on the icon, as the tooltip now manages its own lifecycle
		icon_node.remove_meta("active_tooltip")

func _on_icon_gui_input(event: InputEvent, _icon_node: Control, title: String) -> void:
	if not debug_hover_icons:
		return
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
