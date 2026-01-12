extends TextureProgressBar
class_name UnitStatusIcon

@export var stack_label: InteractiveRichTextLabel

# --- Logic ---
var _current_duration: float = 0.0
var _max_seen_duration: float = 0.1 # Prevent div by zero

func setup(status: Attributes.Status) -> void:
	var icon_texture: Texture2D = Attributes.get_icon(status)
	texture_under = icon_texture
	texture_progress = icon_texture
	step = 0.01

func update_data(stacks: float, _duration: float) -> void:
	# Update Max Duration logic
	# If the new duration is higher than what we've seen, expand the bar
	var duration := _duration
	if duration < 0.0: #i.e. permanent (-1)
		duration = 10000
	if duration > _max_seen_duration:
		_max_seen_duration = duration
	_current_duration = duration
	
	max_value = _max_seen_duration
	min_value = 0.0
	value = _current_duration
	
	# Round stacks for display
	stack_label.text = str(snappedf(stacks, 0.1))

func _process(_delta: float) -> void:
	if _current_duration > 0:
		_current_duration -= Clock.game_delta
		value = _current_duration
