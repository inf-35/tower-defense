extends Node #Tooltip (Tooltip)
#manages the state of the player tooltip (anchored to cursor)

@onready var root: Node = get_tree().get_root()
@onready var tooltips: CanvasLayer = root.get_node("Island").get_node("Tooltips")
var tooltip: Control #current tooltip instance
var cur_tooltip_type: TooltipType #current tooltip type

enum TooltipType { #the type of tooltip instance 
	TOWER_STATS,
	ENEMY_STATS,
	#... add as needed
}

func show_tooltip():
	tooltip.visible = true

func hide_tooltip():
	tooltip.visible = false
	
func update_tooltip_position(new_position: Vector2):
	pass
	
func update_tooltip(required_tooltip_type: TooltipType, tooltip_data : Dictionary):
	if required_tooltip_type != cur_tooltip_type:
		tooltip.free()
		tooltip = Control.new() #TODO: load this from somewhere
		tooltips.add_child(tooltip)
		
	#TODO: implement tooltip data
		
