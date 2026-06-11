extends Panel
class_name RewardPanel

#--- config ---
@export var card_list: VBoxContainer ##the container where cards are spawned
@export var card_scene: PackedScene ##must contain rewardoptioncard script
@export var reroll_button: Button
@export var title_label: InteractiveRichTextLabel ##shared title text driven by RewardService for each reward source

var active_cards: Array[RewardOptionCard] = []

func _ready() -> void:
	if not Run.is_run_ready():
		await Run.references_ready
	visible = false

	#connect to ui bus
	UI.display_reward_choices.connect(_present_options)
	UI.hide_reward_choices.connect(_hide_options)
	UI.update_reroll_cost.connect(_update_reroll_cost)
	UI.update_flux.connect(func(flux): _update_reroll_cost(RewardService.get_reroll_cost()))
	reroll_button.pressed.connect(func():
		UI.reward_rerolled.emit()
	)

	_update_reroll_cost(RewardService.get_reroll_cost())

func _present_options(choices: Array[Reward]) -> void:
	_clear_options()

	visible = true
	reroll_button.visible = RewardService.current_reroll_enabled
	title_label.set_parsed_text(RewardService.current_choice_title)

	for i: int in choices.size():
		var reward_data: Reward = choices[i]
		_instantiate_card(reward_data, i)

func _hide_options() -> void:
	visible = false
	_clear_options()

func _update_reroll_cost(reroll_cost: float) -> void:
	reroll_button.text = "Reroll (%s)" % str(snappedf(reroll_cost, 0.1))
	if Run.player.flux < reroll_cost:
		reroll_button.disabled = true
	else:
		reroll_button.disabled = false

func _instantiate_card(data: Reward, index: int) -> void:
	if not card_scene:
		push_error("RewardUI: No card_scene assigned!")
		return

	var card_instance = card_scene.instantiate() as RewardOptionCard
	if not card_instance:
		push_error("RewardUI: Assigned scene is not a RewardOptionCard.")
		return

	card_list.add_child(card_instance)
	active_cards.append(card_instance)

	#1. setup data and animation
	card_instance.setup(data, index)

	#2. connect signals
	#we bind the index (choice_id) so the ui bus knows which reward was picked
	card_instance.selected.connect(func():
		UI.choice_selected.emit(index)
	)
	card_instance.hovered.connect(func():
		UI.choice_hovered.emit(index)
	)
	card_instance.unhovered.connect(func():
		UI.choice_unhovered.emit(index)
	)

func _clear_options() -> void:
	for card in active_cards:
		card.queue_free()
	active_cards.clear()
