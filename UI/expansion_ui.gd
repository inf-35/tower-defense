extends Panel

@onready var _vbox: VBoxContainer = $VBoxContainer
var option_buttons: Array[Button]

func _ready():
	visible = false
	UI.display_expansion_choices.connect(func(expansion_choices: Array[ExpansionChoice]):
		present_options(expansion_choices)
	)
	UI.hide_expansion_choices.connect(hide_options)
	
func present_options(data: Array[ExpansionChoice]):
	_populate_buttons(data)
	visible = true
	
func hide_options():
	visible = false
	
func _populate_buttons(data: Array[ExpansionChoice]):
	for button: Node in option_buttons:
		button.queue_free()
	option_buttons.clear()
	
	for i: int in len(data):
		var btn := Button.new()
		btn.text = str(i)
		btn.name = "Btn_selection_%s" % str(i)
		btn.pressed.connect(_on_button_pressed.bind(i))
		_vbox.add_child(btn)
		option_buttons.append(btn)
		
func _on_button_pressed(button_id: int):
	UI.choice_selected.emit(button_id)
