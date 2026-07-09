extends RewardOptionCard
class_name ShopOptionCard

@export var price_text: InteractiveRichTextLabel

const UNAFFORDABLE_ALPHA: float = 0.5
const UNAFFORDABLE_BRIGHTNESS: float = 0.8

var _has_gold: bool = true

func setup(reward: Reward, index: int) -> void: ##binds one shop reward and keeps its affordability display synced to the player's current gold
	_reward_data = reward
	#apply data
	_apply_visuals(reward)
	if not UI.update_flux.is_connected(_refresh_affordability):
		UI.update_flux.connect(_refresh_affordability)

	_refresh_affordability(Run.player.flux)

func _refresh_affordability(_flux: float) -> void: ##tints the price and dims the whole card whenever the player cannot currently buy the reward
	if not is_instance_valid(_reward_data):
		return

	_has_gold = Run.player.flux >= _reward_data.price
	var bad_color_hex: String = KeywordService.get_color_hex("bad")
	var price_text_value: String = "%.2f {GOLD%s}" % [_reward_data.price, "|color=%s" % bad_color_hex if not _has_gold else ""]
	if not _has_gold:
		price_text_value = KeywordService.wrap_text(price_text_value, "bad")

	price_text.set_parsed_text(price_text_value)
	_update_card_disabled_state()

func _update_card_disabled_state() -> void:
	if _has_gold and _reward_available:
		modulate = Color.WHITE
		return
	modulate = Color(UNAFFORDABLE_BRIGHTNESS, UNAFFORDABLE_BRIGHTNESS, UNAFFORDABLE_BRIGHTNESS, UNAFFORDABLE_ALPHA)
