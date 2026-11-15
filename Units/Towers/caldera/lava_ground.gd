@tool
extends ColorRect
class_name CalderaLavaGround

const BRUSH_PATCH_SIZE: float = 2.0
const BRUSH_PATCH_JITTER: float = 0.25

@export_range(0.0, 1.0, 0.01) var lavaness: float = 1.0: ##controls how much of the tile the molten pools cover
	set(value):
		lavaness = clampf(value, 0.0, 1.0)
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"lavaness", lavaness)

var _transition: Tween

func _ready() -> void:
	lavaness = lavaness

func bind_brush_patch(mask: Texture2D, bounds: Rect2, cell: Vector2i) -> void: ##maps a stable random patch from the painted centre of the origin tile
	var shader_material := material as ShaderMaterial
	shader_material.set_shader_parameter(&"brush_mask_texture", mask)
	if mask == null or not bounds.has_area():
		shader_material.set_shader_parameter(&"brush_uv_span", Vector2.ZERO)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	var offset := Vector2(
		rng.randf_range(-BRUSH_PATCH_JITTER, BRUSH_PATCH_JITTER),
		rng.randf_range(-BRUSH_PATCH_JITTER, BRUSH_PATCH_JITTER)
	)
	var patch_size: Vector2 = Vector2.ONE * BRUSH_PATCH_SIZE
	var patch_origin: Vector2 = Island.cell_to_position(Vector2i.ZERO) + offset - patch_size * 0.5
	shader_material.set_shader_parameter(&"brush_uv_origin", (patch_origin - bounds.position) / bounds.size)
	shader_material.set_shader_parameter(&"brush_uv_span", patch_size / bounds.size)

func fade_to(amount: float, seconds: float, retire: bool = false) -> void: ##animates coverage and optionally frees the tile after it recedes
	if is_instance_valid(_transition):
		_transition.kill()
	_transition = create_tween()
	_transition.tween_property(self, "lavaness", amount, seconds)
	if retire:
		_transition.tween_callback(queue_free)
