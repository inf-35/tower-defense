extends TextureProgressBar
class_name UnitStatusIcon

@export var stack_label: InteractiveRichTextLabel

const ICON_CANVAS_SIZE: Vector2i = Vector2i(46, 38)
const EFFECT_UNDER_TINT: Color = Color(1.0, 1.0, 1.0, 1.0) ##tint applied to effect-derived statuses

static var _fitted_texture_cache: Dictionary[String, Texture2D] = {}

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
	tint_under = EFFECT_UNDER_TINT

func setup_icon(icon_texture: Texture2D) -> void: ##applies the shared texture-progress presentation for statuses and displayed effects
	add_to_group(DebugAssistant.GROUP_STATUS_ICONS)
	if not is_instance_valid(icon_texture):
		return

	var fitted_texture: Texture2D = _get_aspect_fitted_texture(icon_texture)
	texture_under = fitted_texture
	texture_progress = fitted_texture
	step = 0.01

static func _get_aspect_fitted_texture(icon_texture: Texture2D) -> Texture2D: ##returns a cached icon texture padded to the status-icon canvas without stretching the source art
	var cache_key: String = _get_texture_cache_key(icon_texture)
	if _fitted_texture_cache.has(cache_key):
		return _fitted_texture_cache[cache_key]

	var source_image: Image = icon_texture.get_image()
	if not is_instance_valid(source_image):
		return icon_texture

	var source_size: Vector2i = Vector2i(source_image.get_width(), source_image.get_height())
	if source_size.x <= 0 or source_size.y <= 0:
		return icon_texture

	var fitted_image: Image = source_image.duplicate() as Image
	var fit_scale: float = minf(
		float(ICON_CANVAS_SIZE.x) / float(source_size.x),
		float(ICON_CANVAS_SIZE.y) / float(source_size.y)
	)
	var fitted_size: Vector2i = Vector2i(
		maxi(1, roundi(float(source_size.x) * fit_scale)),
		maxi(1, roundi(float(source_size.y) * fit_scale))
	)
	var offset: Vector2i = Vector2i(
		floori(float(ICON_CANVAS_SIZE.x - fitted_size.x) * 0.5),
		floori(float(ICON_CANVAS_SIZE.y - fitted_size.y) * 0.5)
	)
	var canvas: Image = Image.create(ICON_CANVAS_SIZE.x, ICON_CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	fitted_image.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_LANCZOS)
	canvas.blit_rect(fitted_image, Rect2i(Vector2i.ZERO, fitted_size), offset)

	var fitted_texture: Texture2D = ImageTexture.create_from_image(canvas)
	_fitted_texture_cache[cache_key] = fitted_texture
	return fitted_texture

static func _get_texture_cache_key(icon_texture: Texture2D) -> String:
	if not icon_texture.resource_path.is_empty():
		return icon_texture.resource_path

	return str(icon_texture.get_instance_id())

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
