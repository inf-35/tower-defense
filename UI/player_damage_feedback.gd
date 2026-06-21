extends Control
class_name PlayerDamageFeedback

@export var overlay_rect: ColorRect
@export var peak_intensity: float = 0.8
@export var intensity_per_damage: float = 0.2
@export var fade_duration: float = 0.45
@export var camera_shake_per_damage: float = 0.525
@export var max_camera_shake: float = 1.0

var _material: ShaderMaterial
var _last_hp: float = 0.0
var _has_last_hp: bool = false
var _fade_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = overlay_rect.material as ShaderMaterial
	_material.set_shader_parameter(&"intensity", 0.0)
	UI.update_health.connect(_on_health_updated)

	if Run.has_active_run() and is_instance_valid(Run.player):
		_last_hp = Run.player.hp
		_has_last_hp = true

func _on_health_updated(hp: float) -> void:
	if not _has_last_hp:
		_last_hp = hp
		_has_last_hp = true
		return

	var damage_taken: float = _last_hp - hp
	_last_hp = hp
	if damage_taken <= 0.0:
		return

	_play_hit_sound(damage_taken)
	_flash_vignette(damage_taken)
	_shake_camera(damage_taken)

func _flash_vignette(damage_taken: float) -> void:
	var target_intensity: float = minf(peak_intensity, damage_taken * intensity_per_damage)
	if is_instance_valid(_fade_tween):
		_fade_tween.kill()

	_material.set_shader_parameter(&"intensity", target_intensity)
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_method(_set_intensity, target_intensity, 0.0, fade_duration)

func _set_intensity(value: float) -> void:
	_material.set_shader_parameter(&"intensity", value)

func _play_hit_sound(damage_taken: float) -> void:
	var sound_position: Vector2 = Vector2.ZERO
	if Run.is_run_ready() and is_instance_valid(Run.references.camera):
		sound_position = Run.references.camera.global_position
	Audio.play_sound(ID.Sounds.ENEMY_HIT_SOUND, Audio.get_volume_from_damage(damage_taken), sound_position)

func _shake_camera(damage_taken: float) -> void:
	if not Run.is_run_ready() or not is_instance_valid(Run.references.camera):
		return

	var amount: float = minf(max_camera_shake, damage_taken * camera_shake_per_damage)
	Run.references.camera.add_damage_shake(amount)
