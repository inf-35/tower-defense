extends Panel
#reward_ui
@export var choice_container: Container
var option_buttons: Array[Button]

func _ready():
	visible = false
	UI.display_reward_choices.connect(func(reward_choices: Array[Reward]):
		present_options(reward_choices)
	)
	UI.hide_reward_choices.connect(hide_options)
	
func present_options(data: Array[Reward]):
	_populate_buttons(data)
	visible = true
	
func hide_options():
	visible = false
	
func _populate_buttons(data: Array[Reward]):
	for button: Node in option_buttons:
		button.queue_free()
	option_buttons.clear()
	
	for i: int in len(data):
		var reward: Reward = data[i]
		var btn := Button.new()
		btn.text = str(i)
		btn.name = "Btn_selection_%s" % str(i)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if reward.type == Reward.Type.ADD_RELIC:
			btn.self_modulate = Color(1,1,0.5)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		btn.mouse_entered.connect(_on_choice_hovered.bind(i))
		btn.mouse_exited.connect(_on_choice_unhovered.bind(i))
		
		choice_container.add_child(btn)
		option_buttons.append(btn)
		
func _on_choice_pressed(choice_id: int):
	UI.choice_selected.emit(choice_id)

func _on_choice_hovered(choice_id: int):
	UI.choice_hovered.emit(choice_id)
	
func _on_choice_unhovered(choice_id: int):
	UI.choice_unhovered.emit(choice_id)
