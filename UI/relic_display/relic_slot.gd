extends Control
class_name RelicSlot

@export var frame: TextureRect
@export var icon: TextureRect

func set_slot_offset(offset: Vector2) -> void: ##applies the shared slot-frame offset so the watercolor box can be nudged independently of the relic art
	frame.offset_left = offset.x
	frame.offset_top = offset.y
	frame.offset_right = offset.x
	frame.offset_bottom = offset.y

func set_icon_inset(inset: float) -> void: ##sets the padding used to keep the relic icon comfortably inside the slot frame
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset

func show_empty() -> void: ##shows the slot as empty while preserving the shared frame art
	icon.hide()
	icon.texture = null

func show_icon(texture: Texture2D) -> void: ##shows one relic inside the shared slot frame
	icon.texture = texture
	icon.show()

func get_icon_control() -> TextureRect:
	return icon
