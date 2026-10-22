extends Control
class_name IndexSlot

class Attribute extends RefCounted:
	var key: StringName
	var label: String
	var value: String

	func _init(attribute_key: StringName, attribute_label: String, attribute_value: String) -> void:
		key = attribute_key
		label = attribute_label
		value = attribute_value

signal hover_started(keyword: String)
signal hover_ended

@export var icon_rect: TextureRect ##centered, aspect-preserving entry icon
@export var title_label: Label ##canonical definition name shown below the icon, separate from the overlapping attribute papers
@export var card_panel: PanelContainer ##main card whose bottom edge anchors the independently positioned attribute papers
@export var attribute_strip: HFlowContainer ##overlapping paper strip anchored inside the card; wraps without pushing the card away
@export var attribute_tag_scene: PackedScene ##reusable paper tag instantiated for each supplied attribute
@export_range(0.0, 5.0, 0.1) var tag_splay_degrees: float = 2.0 ##maximum outward paper tilt; stable across index refreshes
@export_range(0.0, 64.0, 1.0) var attribute_bottom_padding: float = 24.0 ##clearance below the strip for authored paper overhang and tilt; does not move the papers

var keyword: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	card_panel.resized.connect(_update_slot_minimum_size)
	attribute_strip.resized.connect(_update_slot_minimum_size)
	_update_slot_minimum_size()

func configure(entry_keyword: String, icon: Texture2D, entry_name: String, attributes: Array[Attribute] = []) -> void: ##replaces the name, icon, and ordered attribute papers without retaining live gameplay objects
	keyword = entry_keyword
	icon_rect.texture = icon
	title_label.text = entry_name
	for child: Node in attribute_strip.get_children():
		attribute_strip.remove_child(child)
		child.queue_free()
	attribute_strip.visible = not attributes.is_empty()
	for index: int in attributes.size():
		var attribute: Attribute = attributes[index]
		var tag: IndexAttributeTag = attribute_tag_scene.instantiate() as IndexAttributeTag
		var splay: float = 0.0
		if attributes.size() > 1:
			splay = lerpf(-tag_splay_degrees, tag_splay_degrees, float(index) / float(attributes.size() - 1))
		tag.configure(attribute.value, splay)
		attribute_strip.add_child(tag)
	if is_node_ready():
		_update_slot_minimum_size()

func _update_slot_minimum_size() -> void: ##reserves only the overlay's protruding space, leaving its card-relative position untouched
	var required_size: Vector2 = card_panel.get_combined_minimum_size()
	required_size.y = maxf(required_size.y, card_panel.position.y + card_panel.size.y)
	if attribute_strip.visible:
		var strip_bottom: float = card_panel.position.y + card_panel.size.y + attribute_strip.offset_top + attribute_strip.size.y
		required_size.y = maxf(required_size.y, strip_bottom + attribute_bottom_padding)
	custom_minimum_size = required_size

func _on_mouse_entered() -> void:
	if not keyword.is_empty():
		hover_started.emit(keyword)

func _on_mouse_exited() -> void:
	hover_ended.emit()
