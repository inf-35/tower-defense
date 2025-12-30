extends ClickyButton
class_name TowerOption

@export var tower_icon : TextureRect
@export var tower_label : InteractiveRichTextLabel

var _hovered_upon : bool = false

func _ready():
	mouse_entered.connect(func(): _hovered_upon = true; _on_hover(_hovered_upon))
	mouse_exited.connect(func(): _hovered_upon = false; _on_hover(_hovered_upon))

func display_tower_type(tower_type : Towers.Type):
	tower_icon.texture = Towers.get_tower_icon(tower_type)
	
	var text : String = ""
	#text = "{T_%s}" % str(Towers.Type.keys()[tower_type]) + "\n"
	text = Towers.get_tower_name(tower_type)+ "\n"
	text += str(Towers.get_tower_cost(tower_type)) + " / " + str(roundi(Towers.get_tower_capacity(tower_type)))
	tower_label.set_parsed_text(text)
	
func _on_hover(_hover : bool):
	pass
