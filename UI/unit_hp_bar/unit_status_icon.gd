extends TextureProgressBar
class_name UnitStatusIcon

@export var stack_label: InteractiveRichTextLabel

#--- logic ---
var _current_duration: float = 0.0
var _max_seen_duration: float = 0.1 #prevent div by zero

func setup(status: Attributes.Status) -> void:
	setup_icon(Attributes.get_icon(status))

func setup_effect(effect_instance: EffectInstance) -> void: ##initialises this icon from an opted-in attached effect prototype
	if not is_instance_valid(effect_instance):
		return
	if not is_instance_valid(effect_instance.effect_prototype):
		return

	setup_icon(effect_instance.effect_prototype.icon)

func setup_icon(icon_texture: Texture2D) -> void: ##applies the shared texture-progress presentation for statuses and displayed effects
	add_to_group(DebugAssistant.GROUP_STATUS_ICONS)
	if not is_instance_valid(icon_texture):
		return

	texture_under = icon_texture
	texture_progress = icon_texture
	step = 0.01

func update_data(stacks: float, _duration: float) -> void:
	#update max duration logic
	#if the new duration is higher than what we've seen, expand the bar
	var duration := _duration
	if duration < 0.0: #i.e. permanent (-1)
		duration = 10000
	if duration > _max_seen_duration:
		_max_seen_duration = duration
	_current_duration = duration

	max_value = _max_seen_duration
	min_value = 0.0
	value = _current_duration

	#round stacks for display
	stack_label.text = str(snappedf(stacks, 0.1))

func _process(_delta: float) -> void:
	if _current_duration > 0:
		_current_duration -= Clock.game_delta
		value = _current_duration
