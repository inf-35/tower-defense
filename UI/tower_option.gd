extends Button
class_name TowerOption

@export var tower_icon : TextureRect
@export var tower_label : Label

var _hovered_upon : bool = false

func _ready():
	mouse_entered.connect(func(): _hovered_upon = true; _on_hover(_hovered_upon))
	mouse_exited.connect(func(): _hovered_upon = false; _on_hover(_hovered_upon))

func display_tower_type(tower_type : Towers.Type):
	tower_icon.texture = preload("res://default_icon.svg") #TODO: integrate thsi with actual data
	tower_label.text = str(Towers.Type.keys()[tower_type]).to_upper() + "\n 40/1" 

func _on_hover(hover : bool):
	pass
