# interactive_rich_text_label.gd
extends RichTextLabel
class_name InteractiveRichTextLabel

var _tooltip_instance: PanelContainer

func _init() -> void:
	# ensure bbcode is enabled
	self.bbcode_enabled = true
	
	# connect to our own signals to handle hovering
	self.meta_hover_started.connect(_on_meta_hover_started)
	self.meta_hover_ended.connect(_on_meta_hover_ended)

# this is the new, clean public API for this component
# all scripts MUST CALL THIS for text modification
func set_parsed_text(_text: String) -> void:
	# use the service to convert user-friendly text into BBCode
	self.text = KeywordService.parse_text_for_bbcode(_text)

func _on_meta_hover_started(meta: Variant) -> void:
	var keyword: String = str(meta)
	var keyword_data: Dictionary = KeywordService.get_keyword_data(keyword)
	
	# create the tooltip and keep a reference to it
	_tooltip_instance = KeywordService.TOOLTIP_PANEL.instantiate()
	add_child(_tooltip_instance)

	if keyword_data:
		_tooltip_instance.show_tooltip(keyword_data)

func _on_meta_hover_ended(meta: Variant) -> void:
	if is_instance_valid(_tooltip_instance):
		_tooltip_instance.free()
