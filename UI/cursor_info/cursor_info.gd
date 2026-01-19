extends Control
class_name CursorInfo

@export var label: InteractiveRichTextLabel
const OFFSET: Vector2 = Vector2(20, 20) # Down-Right from mouse

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE # Click-through
	visible = false
	# Register self to UI singleton for easy access
	UI.cursor_info = self

func _process(_delta: float) -> void:
	if visible:
		# Follow mouse with offset
		var mouse_pos = get_global_mouse_position()
		
		# Clamp to viewport to prevent going off-screen
		var viewport_size = get_viewport_rect().size
		var final_pos = mouse_pos + OFFSET
		
		# Flip horizontally if too far right
		if final_pos.x + size.x > viewport_size.x:
			final_pos.x = mouse_pos.x - size.x - OFFSET.x
			
		# Flip vertically if too far down
		if final_pos.y + size.y > viewport_size.y:
			final_pos.y = mouse_pos.y - size.y - OFFSET.y
			
		global_position = final_pos

func display_message(text: String, is_error: bool = false) -> void:
	if text == "":
		visible = false
		return
		
	visible = true
	label.set_parsed_text(text)
	
	if is_error:
		label.add_theme_color_override("default_color", Color(1.0, 0.4, 0.4))
	else:
		label.remove_theme_color_override("default_color")
