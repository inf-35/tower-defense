extends ClickyButton
class_name ExpansionOptionButton

@export var text_node: InteractiveRichTextLabel

func set_parsed_text(input_text: String) -> void:
	text_node.set_parsed_text(input_text)
