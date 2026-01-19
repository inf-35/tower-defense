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
	text = Towers.get_tower_name(tower_type)
	if Towers.is_tower_rite(tower_type):
		text += " (%s)" % Player.get_rite_count(tower_type)
	text += "\n{GOLD|icon_size=36} " + str(Towers.get_tower_cost(tower_type)) + " {POPULATION|icon_size=36} " + str(Towers.get_tower_capacity(tower_type))
	tower_label.set_parsed_text(text)
	
func _on_hover(_hover : bool):
	pass
