extends MarginContainer
class_name IndexAttributeTag

@export var paper: PanelContainer ##rotated paper inside the unrotated layout footprint
@export var paper_frame: Control ##unrotated measuring frame so container layout cannot reset the paper tilt
@export var value_label: Label ##content-sized attribute value using the shared ink styling

func _ready() -> void:
	paper.minimum_size_changed.connect(_on_paper_minimum_size_changed)
	paper.resized.connect(_on_paper_resized)
	_on_paper_minimum_size_changed()
	_on_paper_resized()

func configure(value: String, splay_degrees: float) -> void: ##sets presentation only; the supplying page owns attribute meaning
	value_label.text = value
	paper.rotation_degrees = splay_degrees

func _on_paper_minimum_size_changed() -> void: ##passes text measurements through the plain control that isolates paper rotation
	paper_frame.custom_minimum_size = paper.get_combined_minimum_size()

func _on_paper_resized() -> void: ##keeps the tilt centered after the native containers measure the text
	paper.pivot_offset = paper.size * 0.5
