extends UnitComponent
class_name BuffComponent

const LINK_WISP_VFX: VFXInfo = preload("res://Content/CommonVisuals/buff_link_wisp.tres")
const LINK_WISP_PROJECTILE_SPEED: float = 120.0
const LINK_WISP_GRAVITY: float = 400.0
const LINK_WISP_MINIMUM_FLIGHT_TIME: float = 0.16
const LINK_WISP_MAXIMUM_FLIGHT_TIME: float = 0.48
const BONUS_TEXT_COLOR: Color = Color(0.44, 0.405, 0.136, 1.0)
const ACTIVATION_OVERLAY_COLOR: Color = Color(1.381, 0.972, 0.0, 1.0)
const BONUS_TEXT_PEAK_ALPHA: float = 1.00
const BONUS_TEXT_RAMP_UP_RATIO: float = 0.1
const BONUS_TEXT_FADE_OUT_RATIO: float = 0.3
const ACTIVATION_OVERLAY_PEAK_STRENGTH: float = 0.55
const ACTIVATION_RAMP_IN_DURATION: float = 0.5
const ACTIVATION_FADE_OUT_DURATION: float = 0.1

func get_short_name() -> String: ##returns the authored or derived short buff label used by shared presentation helpers
	if not unit is Tower:
		return ""

	return Towers.get_buff_short_name((unit as Tower).type)

func show_bonus_text(world_pos: Vector2, text_override: String = "") -> void: ##shows the shared buff-owned popup in a bright yellow, text-first format
	var display_text: String = text_override
	if display_text.is_empty():
		var short_name: String = get_short_name()
		if short_name.is_empty():
			return
		display_text = "+%s" % short_name

	if not is_instance_valid(UI.floating_text_manager):
		return

	UI.floating_text_manager.show_text_with_profile(
		display_text,
		world_pos,
		BONUS_TEXT_COLOR,
		BONUS_TEXT_PEAK_ALPHA,
		BONUS_TEXT_RAMP_UP_RATIO,
		BONUS_TEXT_FADE_OUT_RATIO,
		1.0,
		true,
		0.5,
	)

func activate_new_link(target: Tower, show_link_wisp: bool = true) -> void: ##plays first-link feedback and optionally carries its source-to-target relationship through a wisp
	activate_target(target, "", null, show_link_wisp)

func activate_target(target: Tower, text_override: String = "", icon_override: Texture2D = null, show_link_wisp: bool = true) -> void: ##plays shared yellow buff feedback on a target with optional icon, text, and causal link wisp
	if not is_instance_valid(target):
		return

	if show_link_wisp:
		play_link_wisp(unit, target)

	if is_instance_valid(icon_override) and is_instance_valid(UI.floating_text_manager):
		UI.floating_text_manager.show_icon(icon_override, target.global_position)

	show_bonus_text(target.global_position, text_override)

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

static func play_link_wisp(source: Unit, target: Unit) -> void: ##launches the shared buff wisp from one live unit to another without involving combat delivery
	if not is_instance_valid(source):
		return
	play_link_wisp_from_position(source.global_position, target)

static func play_link_wisp_from_position(source_position: Vector2, target: Unit) -> void: ##launches from a captured position so dead or transient causes remain representable
	if not is_instance_valid(target):
		return
	play_link_wisp_between_positions(source_position, target.global_position)

static func play_link_wisp_between_positions(source_position: Vector2, target_position: Vector2) -> void: ##delegates the buff-owned profile to the generic point-to-point vfx launcher
	VFXManager.play_ballistic_vfx(
		LINK_WISP_VFX,
		source_position,
		target_position,
		LINK_WISP_PROJECTILE_SPEED,
		LINK_WISP_GRAVITY,
		LINK_WISP_MINIMUM_FLIGHT_TIME,
		LINK_WISP_MAXIMUM_FLIGHT_TIME,
		Vector2.ONE,
		true
	)

func get_save_data() -> Dictionary:
	return {}
