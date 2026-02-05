extends RewardOptionCard
class_name ShopOptionCard

@export var price_text: InteractiveRichTextLabel

func setup(reward: Reward, index: int) -> void:
	_reward_data = reward
	# apply Data
	_apply_visuals(reward)
	
	price_text.set_parsed_text("%.2f {GOLD}" % reward.price)
