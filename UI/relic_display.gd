extends GridContainer
class_name RelicDisplay

# --- configuration ---
@export var icon_size: Vector2 = Vector2(48, 48)
@export var icon_stretch_mode: TextureRect.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

func _ready() -> void:
	UI.update_relics.connect(_refresh_display)
	
	#initial population
	_refresh_display()

func _refresh_display() -> void:
	for child in get_children():
		child.queue_free()
	
	# iterate through player relics
	var relics: Array[RelicData] = Player.active_relics
	
	for relic: RelicData in relics:
		_create_relic_icon(relic)

func _create_relic_icon(relic: RelicData) -> void:
	# We use a simple TextureRect for the visual representation.
	var icon_node := TextureRect.new()

	icon_node.texture = relic.icon
	
	# visual formatting
	icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_node.stretch_mode = icon_stretch_mode
	icon_node.custom_minimum_size = icon_size
	
	# enable mouse interaction so we can detect hovers
	icon_node.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# connect signals for tooltip logic
	# bind the 'relic' data so the handler knows what to display
	icon_node.mouse_entered.connect(_on_icon_hovered.bind(icon_node, relic))
	icon_node.mouse_exited.connect(_on_icon_unhovered.bind(icon_node))
	
	add_child(icon_node)

# --- Tooltip Integration ---

func _on_icon_hovered(icon_node: Control, relic: RelicData) -> void:
	# 1. Construct the data packet expected by TooltipPanel
	# We try to dynamically resolve 'title' and 'description' from the RelicData resource
	var tooltip_data: Dictionary = {
		"title": relic.title,
		"description": relic.description,
		"icon": relic.icon
	}
	
	# 2. Instantiate the standardized tooltip panel
	# We use the factory scene from KeywordService to ensure consistency across the game
	var tooltip_instance: TooltipPanel = KeywordService.TOOLTIP_PANEL.instantiate()
	
	# 3. Add to the Scene Root (Top Level)
	# This ensures the tooltip draws above all other UI elements and isn't clipped by containers
	add_child(tooltip_instance)
	
	# 4. Display the data
	# This triggers the TooltipPanel's internal 'solidify' timer logic automatically
	tooltip_instance.show_tooltip(tooltip_data)
	
	# 5. Store a reference to the active tooltip on the icon itself.
	# This allows us to retrieve and close the specific tooltip instance later.
	icon_node.set_meta("active_tooltip", tooltip_instance)

func _on_icon_unhovered(icon_node: Control) -> void:
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
