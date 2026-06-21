extends UnitComponent
class_name BuffComponent

const BONUS_TEXT_COLOR: Color = Color(1.0, 0.92, 0.28, 1.0)
const ACTIVATION_OVERLAY_COLOR: Color = Color(1.2, 0.997, 0.522, 1.0)
const BONUS_TEXT_PEAK_ALPHA: float = 1.00
const BONUS_TEXT_RAMP_UP_RATIO: float = 0.75
const BONUS_TEXT_FADE_OUT_RATIO: float = 0.25
const ACTIVATION_OVERLAY_PEAK_STRENGTH: float = 0.55
const ACTIVATION_RAMP_IN_DURATION: float = 0.6
const ACTIVATION_FADE_OUT_DURATION: float = 0.15

func get_short_name() -> String: ##returns the authored or derived short buff label used by shared presentation helpers
	if not unit is Tower:
		return ""

	return Towers.get_buff_short_name((unit as Tower).type)

func show_bonus_text(world_pos: Vector2) -> void: ##shows the shared buff-owned popup in a bright yellow, text-first format
	var short_name: String = get_short_name()
	if short_name.is_empty() or not is_instance_valid(UI.floating_text_manager):
		return

	UI.floating_text_manager.show_text_with_profile(
		"+%s" % short_name,
		world_pos,
		BONUS_TEXT_COLOR,
		BONUS_TEXT_PEAK_ALPHA,
		BONUS_TEXT_RAMP_UP_RATIO,
		BONUS_TEXT_FADE_OUT_RATIO,
		1.2,
		true
	)

func activate_new_link(target: Tower) -> void: ##plays the shared first-link buff activation feedback on a newly affected tower
	if not is_instance_valid(target):
		return

	show_bonus_text(target.global_position)

	target.pulse_tint_layer(
		TintService.LAYER_RITE_PULSE,
		ACTIVATION_OVERLAY_COLOR,
		ACTIVATION_OVERLAY_PEAK_STRENGTH,
		ACTIVATION_RAMP_IN_DURATION,
		ACTIVATION_FADE_OUT_DURATION,
		false,
		Tween.TRANS_QUAD,
		Tween.EASE_OUT,
		true
	)

func get_save_data() -> Dictionary:
	return {}
