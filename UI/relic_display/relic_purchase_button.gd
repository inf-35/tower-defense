extends ClickyButton
class_name RelicPurchaseButton

const DISABLED_MODULATE: Color = Color(0.8, 0.8, 0.8, 0.55)

@export var motion: AnimatableUI
@export var icon: TextureRect
@export var cost_label: InteractiveRichTextLabel

func _ready() -> void:
	set_motion_target(motion)

func configure(offset: Vector2, affordable: bool, cost: float) -> void: ##applies the shared slot-art offset, affordability state, and parsed gold text inside one scene-owned purchase slot
	icon.offset_left = offset.x
	icon.offset_top = offset.y
	icon.offset_right = offset.x
	icon.offset_bottom = offset.y
	disabled = not affordable
	modulate = Color.WHITE if affordable else DISABLED_MODULATE
	var cost_text: String = "%.0f {GOLD}" % cost
	if not affordable:
		cost_text = KeywordService.wrap_text(cost_text, "bad")
	cost_label.set_parsed_text(cost_text)
