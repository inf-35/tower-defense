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
		btn.pressed.connect(_on_choice_pressed.bind(i))
		btn.mouse_entered.connect(_on_choice_hovered.bind(i))
		btn.mouse_exited.connect(_on_choice_unhovered.bind(i))
		
		_vbox.add_child(btn)
		option_buttons.append(btn)
		
func _on_choice_pressed(choice_id: int):
	UI.choice_selected.emit(choice_id)

func _on_choice_hovered(choice_id: int):
	UI.choice_hovered.emit(choice_id)
	
func _on_choice_unhovered(choice_id: int):
	UI.choice_unhovered.emit(choice_id)
