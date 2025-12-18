extends PanelContainer
class_name TooltipPanel

# --- configuration ---
const SOLIDIFY_TIME: float = 0.5
const GRACE_TIME: float = 0.3 # time allowed to move mouse from link to panel
const MOUSE_OFFSET: Vector2 = Vector2(20, 20)

# --- visual references ---
@export var title_label: InteractiveRichTextLabel
@export var description_label: InteractiveRichTextLabel

# --- state ---
var _solidify_timer: Timer
var _grace_timer: Timer

var is_solidified: bool = false:
	set(new):
		is_solidified = new
		if not is_solidified:
			print("solidity: ", is_solidified, " at ", Time.get_ticks_msec())
var is_mouse_inside_panel: bool = false
var is_mouse_on_link: bool = true # assumed true when created

# --- hierarchy ---
var parent_tooltip: TooltipPanel = null
var active_child_tooltip: TooltipPanel = null

func _init():
	_setup_timers()

func _ready() -> void:
	self.visible = false
	self.top_level = true

	# enable mouse detection on the panel itself
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_panel_mouse_entered)
	mouse_exited.connect(_on_panel_mouse_exited)

func _setup_timers() -> void:
	_solidify_timer = Timer.new()
	_solidify_timer.one_shot = true
	_solidify_timer.wait_time = SOLIDIFY_TIME
	_solidify_timer.timeout.connect(_on_solidify_timeout)
	add_child(_solidify_timer)
	
	_grace_timer = Timer.new()
	_grace_timer.one_shot = true
	_grace_timer.wait_time = GRACE_TIME
	_grace_timer.timeout.connect(_on_grace_timeout)
	add_child(_grace_timer)

func _process(_delta: float) -> void:
	if not visible:
		return
		
	# stop moving if solidified
	if is_solidified:
		return
		
	_movement_logic()

func _movement_logic():
	var viewport_rect: Rect2 = get_viewport_rect()
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var panel_size: Vector2 = self.size
	var final_pos: Vector2 = mouse_pos + MOUSE_OFFSET

	if final_pos.x + panel_size.x > viewport_rect.size.x:
		final_pos.x = mouse_pos.x - panel_size.x - MOUSE_OFFSET.x
	if final_pos.y + panel_size.y > viewport_rect.size.y:
		final_pos.y = mouse_pos.y - panel_size.y - MOUSE_OFFSET.y

	final_pos.x = clamp(final_pos.x, 0, viewport_rect.size.x - panel_size.x)
	final_pos.y = clamp(final_pos.y, 0, viewport_rect.size.y - panel_size.y)
	
	self.global_position = final_pos

func show_tooltip(data: Dictionary, parent: TooltipPanel = null) -> void:
	# hierarchy management
	parent_tooltip = parent
	if is_instance_valid(parent_tooltip):
		parent_tooltip.register_child(self)
	
	title_label.set_parsed_text(data.get(&"title", "N/A"))
	description_label.set_parsed_text(data.get(&"description", ""))
	
	self.visible = true
	
	# start the countdown to lock the tooltip in place
	_solidify_timer.start()

# called by InteractiveRichTextLabel when the mouse leaves the specific keyword text
func on_link_mouse_exited() -> void:
	is_mouse_on_link = false

	if not is_solidified:
		# if not solid yet, leaving the link kills it immediately
		close()
	else:
		# if solid, give the user a split second to move mouse from text to the panel
		_grace_timer.start()

func _on_solidify_timeout() -> void:
	is_solidified = true
	# visual feedback could go here (e.g. slight border color change)

func _on_grace_timeout() -> void:
	# if the grace period ended and the mouse isn't inside the panel, close it.
	if (not is_mouse_inside_panel) and (not is_mouse_on_link) :
		close()

func _on_panel_mouse_entered() -> void:
	is_mouse_inside_panel = true
	# if we entered the panel during the grace period, stop the death timer
	if not _grace_timer.is_stopped():
		_grace_timer.stop()

func _on_panel_mouse_exited() -> void:
	is_mouse_inside_panel = false
	if _grace_timer.is_inside_tree():
		_grace_timer.start()

# hierarchy helpers
func register_child(child: TooltipPanel) -> void:
	# if we already had a child open, close it (only one nested tip at a time)
	if is_instance_valid(active_child_tooltip) and active_child_tooltip != child:
		active_child_tooltip.close()
	active_child_tooltip = child

func close() -> void:
	# recursive cleanup: close children first
	if is_instance_valid(active_child_tooltip):
		active_child_tooltip.close()
	
	queue_free()
