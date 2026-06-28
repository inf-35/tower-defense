extends Control
class_name RewardPickupAnimator

@export var relic_target: Control
@export var tower_target: Control

const TRAVEL_DURATION: float = 0.46
const ARC_HEIGHT: float = 72.0
const START_SCALE: Vector2 = Vector2(1.0, 1.0)
const END_SCALE: Vector2 = Vector2(0.42, 0.42)

func _ready() -> void: ##registers the animator as a lightweight hud service so reward/shop cards can launch fly-to-bar feedback without bespoke scene-tree lookups
	UI.reward_pickup_animator = self
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Run.is_run_ready():
		await Run.references_ready
	if not Run.player.rite_excavated.is_connected(_on_rite_excavated):
		Run.player.rite_excavated.connect(_on_rite_excavated)

func play_reward_pickup(reward: Reward, icon_texture: Texture2D, source_position: Vector2) -> void: ##spawns one detached icon and flies it from a reward card toward the relevant hud collection target
	if not is_instance_valid(reward):
		return
	if not is_instance_valid(icon_texture):
		return

	var target_position: Vector2 = _get_target_position(reward)
	if target_position == Vector2.INF:
		return

	_play_icon_pickup(icon_texture, source_position, target_position)

func _on_rite_excavated(tower: Tower) -> void: ##returns excavated rites to the sidebar with the same pickup arc used by reward/shop unlocks
	if not is_instance_valid(tower):
		return
	if not is_instance_valid(tower_target):
		return

	var source_position: Vector2 = tower.get_global_transform_with_canvas().origin
	if is_instance_valid(tower.graphics):
		source_position = tower.graphics.get_global_transform_with_canvas().origin

	_play_icon_pickup(Towers.get_tower_icon(tower.type), source_position, tower_target.get_global_rect().get_center())

func _play_icon_pickup(icon_texture: Texture2D, source_position: Vector2, target_position: Vector2) -> void: ##shared icon flight used by both reward cards and excavated rites so all pickup feedback stays visually consistent
	if not is_instance_valid(icon_texture):
		return
	if target_position == Vector2.INF:
		return

	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(120, 120)
	icon.size = icon.custom_minimum_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	icon.pivot_offset = icon.custom_minimum_size * 0.5
	add_child(icon)
	icon.position = source_position - icon.size * 0.5
	icon.scale = START_SCALE

	var start_position: Vector2 = icon.position
	var end_position: Vector2 = target_position - icon.size * END_SCALE * 0.5
	var arc_peak: Vector2 = start_position.lerp(end_position, 0.5) + Vector2(0.0, -ARC_HEIGHT)

	var tween: Tween = create_tween().set_parallel(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(
		func(progress: float) -> void:
			if not is_instance_valid(icon):
				return
			var a: Vector2 = start_position.lerp(arc_peak, progress)
			var b: Vector2 = arc_peak.lerp(end_position, progress)
			icon.position = a.lerp(b, progress),
		0.0,
		1.0,
		TRAVEL_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "scale", END_SCALE, TRAVEL_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "modulate:a", 0.0, TRAVEL_DURATION * 0.35).set_delay(TRAVEL_DURATION * 0.65)
	tween.finished.connect(icon.queue_free)

func _get_target_position(reward: Reward) -> Vector2: ##routes each pickup family toward the correct persistent hud destination
	match reward.type:
		Reward.Type.ADD_RELIC:
			if is_instance_valid(relic_target):
				return relic_target.get_global_rect().get_center()
		Reward.Type.UNLOCK_TOWER, Reward.Type.ADD_RITE:
			if is_instance_valid(tower_target):
				return tower_target.get_global_rect().get_center()
	return Vector2.INF
