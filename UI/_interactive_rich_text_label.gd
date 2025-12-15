# interactive_rich_text_label.gd
extends RichTextLabel
class_name InteractiveRichTextLabel

var _tooltip_instance: TooltipPanel

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
	
	if keyword_data:
		if _tooltip_instance: _tooltip_instance.close()
		_tooltip_instance = KeywordService.TOOLTIP_PANEL.instantiate()
		
		# determine if *this* label is currently sitting inside another tooltip
		var parent_tooltip: TooltipPanel = _find_parent_tooltip()
		print("added tooltip,  ", parent_tooltip)

		add_child(_tooltip_instance)
		
		_tooltip_instance.show_tooltip(keyword_data, parent_tooltip)

func _on_meta_hover_ended(_meta: Variant) -> void:
	# INSTEAD of freeing immediately, we tell the tooltip the mouse left the link
	if is_instance_valid(_tooltip_instance):
		_tooltip_instance.on_link_mouse_exited()
		# we release our reference, the tooltip now manages its own lifecycle

# helper to check hierarchy up the tree
func _find_parent_tooltip() -> TooltipPanel:
	var candidate = get_parent()
	while candidate:
		if candidate is TooltipPanel:
			return candidate
		candidate = candidate.get_parent()
	return null
