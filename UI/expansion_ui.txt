extends Panel

@export var _vbox: VBoxContainer
var option_buttons: Array[Button]
var _pending_choice_id: int
var _confirmation_button: Button

func _ready():
	visible = false
	UI.display_expansion_choices.connect(func(expansion_choices: Array[ExpansionChoice]):
		_present_options(expansion_choices)
	)
	UI.hide_expansion_choices.connect(_hide_options)
	UI.display_expansion_confirmation.connect(_present_confirmation)
	UI.hide_expansion_confirmation.connect(_hide_confirmation)
	
func _present_options(data: Array[ExpansionChoice]):
	_populate_buttons(data)
	visible = true
	
func _hide_options():
	visible = false
	
func _present_confirmation(pending_choice_id: int):
	if not is_instance_valid(_confirmation_button):
		return
		
	self._pending_choice_id = pending_choice_id
	_confirmation_button.modulate = Color.WHITE
	_confirmation_button.disabled = false

func _hide_confirmation():
	if not is_instance_valid(_confirmation_button):
		return
	_confirmation_button.modulate = Color.TRANSPARENT
	_confirmation_button.disabled = true
	
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
		
	_confirmation_button = Button.new()
	_confirmation_button.text = "Apply expansion."
	_confirmation_button.pressed.connect(_on_confirmation_pressed)
	_confirmation_button.modulate = Color.TRANSPARENT #we dont toggle visibility so as to not affect formatting
	_confirmation_button.disabled = true
	_vbox.add_child(_confirmation_button)
		
func _on_choice_pressed(choice_id: int):
	UI.choice_focused.emit(choice_id)

func _on_choice_hovered(choice_id: int):
	UI.choice_hovered.emit(choice_id)
	
func _on_choice_unhovered(choice_id: int):
	UI.choice_unhovered.emit(choice_id)

func _on_confirmation_pressed():
	UI.choice_selected.emit(_pending_choice_id)
