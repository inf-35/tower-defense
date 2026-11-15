extends Control

const DIRECTIONS: Array[Vector2] = [
	Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN,
	Vector2(-0.70710678, -0.70710678), Vector2(0.70710678, -0.70710678),
	Vector2(-0.70710678, 0.70710678), Vector2(0.70710678, 0.70710678),
]

@export var panel: PanelContainer ##paper face whose actual style supplies the outline silhouette
@export_range(0.0, 8.0, 0.25) var outline_width: float = 5.0: ##border thickness in local ui pixels, scaling with the button's motion
	set(value):
		outline_width = value
		queue_redraw()

func _ready() -> void:
	panel.resized.connect(queue_redraw)
	panel.theme_changed.connect(queue_redraw)

func _draw() -> void: ##draws behind the original paper, preserving its nine-slice margins and tiled edges
	if panel == null or outline_width <= 0.0:
		return
	var paper_style: StyleBox = panel.get_theme_stylebox(&"panel")
	#panel containers place children inside content margins; align the copies with the paper itself.
	for direction: Vector2 in DIRECTIONS:
		draw_style_box(paper_style, Rect2(direction * outline_width - position, panel.size))
