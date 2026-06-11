extends RewardOptionCard
class_name ShopOptionCard

@export var price_text: InteractiveRichTextLabel

const UNAFFORDABLE_ALPHA: float = 0.72

func setup(reward: Reward, index: int) -> void:
	_reward_data = reward
	#apply data
	_apply_visuals(reward)
	UI.update_flux.connect(_refresh_affordability)

	_refresh_affordability(Run.player.flux)

func _refresh_affordability(_flux: float) -> void:
	if not is_instance_valid(_reward_data):
		return

	var has_gold: bool = Run.player.flux >= _reward_data.price
	var price_text_value: String = "%.2f {GOLD%s}" % [_reward_data.price, "|color=red" if not has_gold else ""]
	if not has_gold:
		price_text_value = "[color=red]%s[/color]" % price_text_value

	price_text.set_parsed_text(price_text_value)
	modulate.a = 1.0 if has_gold else UNAFFORDABLE_ALPHA
