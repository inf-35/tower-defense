# line_drawer.gd
extends Control
class_name LineDrawer

# --- configuration ---
# export these properties so you can style the line in the inspector
@export var line_color: Color = Color.WHITE
@export var line_width: float = 3.0
@export var line_cap_style: Line2D.LineCapMode = Line2D.LINE_CAP_ROUND

# --- node references ---
# this will hold a reference to the main timeline node
@export var _timeline: WaveTimeline

func _ready() -> void:
	# we expect this node to be a child of the WaveTimeline
	_timeline = get_parent() as WaveTimeline
	if not is_instance_valid(_timeline):
		set_process(false)

func _process(_delta: float) -> void:
	queue_redraw()

# this is the main drawing function, called by the engine
func _draw() -> void:
	if not is_instance_valid(_timeline) or _timeline._pip_nodes.size() < 2:
		return # do nothing if there are not enough pips to draw a line

	# get the start and end points from the first and last pips in the timeline's array.
	# because the pips use a pivot offset, their 'position' is their center.
	var start_point: Vector2 = _timeline._pip_nodes.front().position
	var end_point: Vector2 = _timeline._pip_nodes.back().position
	
	# draw a single, continuous line between the center of the first and last pip
	draw_line(start_point, end_point, line_color, line_width)
	
	# optional: draw round caps for a softer look
	draw_circle(start_point, line_width / 2.0, line_color)
	draw_circle(end_point, line_width / 2.0, line_color)
