extends Panel

@onready var _vbox: VBoxContainer = $VBoxContainer
var option_buttons: Array[Button]

func _ready():
	visible = false
	Phases.display_expansion_choices.connect(func(expansion_choices: Array[ExpansionChoice]):
		present_options()
	)
	Phases.expansion_phase_ended.connect(hide_options)
	
func present_options():
	_populate_buttons()
	visible = true
	
func hide_options():
	visible = false
	
func _populate_buttons():
	for button: Node in option_buttons:
		button.queue_free()
	option_buttons.clear()
	
	for i in Waves.EXPANSION_CHOICES:
		var btn := Button.new()
		btn.text = str(i)
		btn.name = "Btn_selection_%s" % str(i)
		btn.pressed.connect(_on_button_pressed.bind(i))
		_vbox.add_child(btn)
		option_buttons.append(btn)
		
func _on_button_pressed(button: int):
	Phases.player_chose_expansion(button)
