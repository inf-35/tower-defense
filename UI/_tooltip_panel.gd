# tooltip_panel.gd
extends PanelContainer
class_name TooltipPanel

@export var title_label: InteractiveRichTextLabel
@export var description_label: InteractiveRichTextLabel

const MOUSE_OFFSET: Vector2 = Vector2(20, 20)

func _ready() -> void:
	# start hidden and make sure it's rendered on top of everything else
	self.visible = false
	self.top_level = true

func _process(delta: float) -> void:
	if not self.visible:
		return

	# --- 1. get required data ---
	var viewport_rect: Rect2 = get_viewport_rect()
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var panel_size: Vector2 = self.size

	# --- 2. stage 1: intelligent flipping (preferred position) ---
	# start with the default desired position: to the bottom-right of the cursor.
	var final_pos: Vector2 = mouse_pos + MOUSE_OFFSET

	# check right edge: if we would go off-screen...
	if final_pos.x + panel_size.x > viewport_rect.size.x:
		# ...flip to be on the left side of the cursor instead.
		final_pos.x = mouse_pos.x - panel_size.x - MOUSE_OFFSET.x
		
	# check bottom edge: if we would go off-screen...
	if final_pos.y + panel_size.y > viewport_rect.size.y:
		# ...flip to be on the top side of the cursor instead.
		final_pos.y = mouse_pos.y - panel_size.y - MOUSE_OFFSET.y

	# --- 3. stage 2: absolute clamping (foolproof safeguard) ---
	# after flipping, clamp the final position to ensure it never, ever leaves the screen.
	# this handles corner cases and situations where the tooltip is larger than the window.
	final_pos.x = clamp(final_pos.x, 0, viewport_rect.size.x - panel_size.x)
	final_pos.y = clamp(final_pos.y, 0, viewport_rect.size.y - panel_size.y)
	
	# --- 4. apply final position ---
	self.global_position = final_pos
func show_tooltip(data: Dictionary) -> void:
	title_label.set_parsed_text(data.get(&"title", "N/A"))
	description_label.set_parsed_text(data.get(&"description", ""))
	self.visible = true

func hide_tooltip() -> void:
	self.visible = false
