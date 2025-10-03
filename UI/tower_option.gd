extends ClickyButton
class_name TowerOption

@export var tower_icon : TextureRect
@export var tower_label : Label

var _hovered_upon : bool = false

func _ready():
	mouse_entered.connect(func(): _hovered_upon = true; _on_hover(_hovered_upon))
	mouse_exited.connect(func(): _hovered_upon = false; _on_hover(_hovered_upon))

func display_tower_type(tower_type : Towers.Type):
	tower_icon.texture = Towers.get_tower_icon(tower_type)
	tower_label.text = str(Towers.Type.keys()[tower_type]).to_upper() + "\n"
	tower_label.text += str(Towers.get_tower_cost(tower_type)) + " / " + str(roundi(Towers.get_tower_capacity(tower_type)))

func _on_hover(hover : bool):
	pass
