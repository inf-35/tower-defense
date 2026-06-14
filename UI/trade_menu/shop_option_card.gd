extends RewardOptionCard
class_name ShopOptionCard

@export var price_text: InteractiveRichTextLabel

const UNAFFORDABLE_ALPHA: float = 0.72

func setup(reward: Reward, index: int) -> void: ##binds one shop reward and keeps its affordability display synced to the player's current gold
	_reward_data = reward
	#apply data
	_apply_visuals(reward)
	if not UI.update_flux.is_connected(_refresh_affordability):
		UI.update_flux.connect(_refresh_affordability)

	_refresh_affordability(Run.player.flux)

func _refresh_affordability(_flux: float) -> void: ##tints the price and fades the whole card whenever the player cannot currently buy the reward
	if not is_instance_valid(_reward_data):
		return

	var has_gold: bool = Run.player.flux >= _reward_data.price
	var bad_color_hex: String = KeywordService.get_bad_color_hex()
	var price_text_value: String = "%.2f {GOLD%s}" % [_reward_data.price, "|color=%s" % bad_color_hex if not has_gold else ""]
	if not has_gold:
		price_text_value = KeywordService.wrap_bad_text(price_text_value)

	price_text.set_parsed_text(price_text_value)
	modulate.a = 1.0 if has_gold else UNAFFORDABLE_ALPHA
