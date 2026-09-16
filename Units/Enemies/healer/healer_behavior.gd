extends Behavior
class_name HealerBehavior

const AURA_RING_TEXTURE: Texture2D = preload("res://Assets/enemy_aura_ring.png")
const AURA_RING_COLOR: Color = Color(0.2, 1.0, 0.4, 0.8)
const AURA_RING_START_RADIUS: float = 10.0
const AURA_RING_PULSE_DURATION: float = 0.5

#--- configuration ---
@export var heal_amount: float = 0.0 ##amount of hp points
@export var heal_interval: float = 3.0 ##interval (in seconds) between heals
@export var heal_range: float = 10.0

#--- state ---
var _heal_area: Area2D
var _allies_in_range: Array[Unit] = []

func start() -> void:
	super.start()
	_setup_ally_detection()
	#healers move towards the objective like normal units
	_attempt_navigate_to_origin()

func detach() -> void:
	if is_instance_valid(_heal_area):
		_heal_area.free()

func update(_delta: float) -> void:
	_attempt_simple_attack()
	#update the cooldown timer
	_cooldown += Clock.game_delta

	#1. attempt to heal if off cooldown
	if _cooldown >= heal_interval:
		if _perform_heal_pulse():
			_cooldown = 0.0

func _setup_ally_detection() -> void:
	_heal_area = Area2D.new()
	_heal_area.name = "HealAura"
	unit.add_child(_heal_area)

	var shape := CircleShape2D.new()
	shape.radius = heal_range

	var collision := CollisionShape2D.new()
	collision.shape = shape
	_heal_area.add_child(collision)

	#scan for allied units
	_heal_area.collision_layer = 0
	_heal_area.collision_mask = Hitbox.get_mask(unit.hostile)
	_heal_area.monitorable = false
	_heal_area.monitoring = true
	
	for area in _heal_area.get_overlapping_areas(): #record all ialready existing intersections (includes this unit also)
		_on_ally_entered(area)

	_heal_area.area_entered.connect(_on_ally_entered)
	_heal_area.area_exited.connect(_on_ally_exited)

func _on_ally_entered(area: Area2D) -> void:
	#ensure we are detecting a unit's hitbox
	if not area is Hitbox:
		return

	var ally_unit: Unit = area.unit
	if not is_instance_valid(ally_unit):
		return

	#optional: don't heal self
	if ally_unit == unit:
		return

	if not _allies_in_range.has(ally_unit):
		_allies_in_range.append(ally_unit)

func _on_ally_exited(area: Area2D) -> void:
	if not area is Hitbox:
		return

	var ally_unit: Unit = area.unit
	if _allies_in_range.has(ally_unit):
		_allies_in_range.erase(ally_unit)

func _perform_heal_pulse() -> bool:
	var did_heal_anyone: bool = false

	#1. prune invalid instances (dead units)
	#this uses a custom filter to remove null/freed instances efficiently
	var valid_allies: Array[Unit] = []
	for ally in _allies_in_range:
		if is_instance_valid(ally) and is_instance_valid(ally.health_component):
			valid_allies.append(ally)
	_allies_in_range = valid_allies

	#2. apply heal
	for ally: Unit in _allies_in_range:
		var health_comp: HealthComponent = ally.health_component

		#the health setter in healthcomponent automatically clamps to max_health
		health_comp.health += heal_amount
		did_heal_anyone = true
		_spawn_heal_vfx(ally)

	_play_animation(&"cast") #assuming an animation exists
	_spawn_pulse_vfx()

	#return true to reset cooldown, even if we didn't heal anyone?
	#usually yes, to maintain the rhythm, or false to heal immediately when someone gets hurt.
	#here we return true only if we acted, or strictly strictly adhere to interval.
	#let's strictly adhere to interval to prevent spam-checking.
	return true

#--- visuals ---

func _spawn_heal_vfx(target: Unit) -> void:
	#simple scale pulse keeps this feedback independent from the shared tint stack
	if not is_instance_valid(target.graphics):
		return

	var tween: Tween = create_tween()
	tween.tween_property(target, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(target, "scale", Vector2(1.0, 1.0), 0.1)

func _spawn_pulse_vfx() -> void:
	_spawn_aura_ring_pulse(AURA_RING_COLOR)

func _spawn_aura_ring_pulse(pulse_color: Color) -> void:
	if not is_instance_valid(unit):
		return

	var texture_size: Vector2 = AURA_RING_TEXTURE.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	var pulse: Sprite2D = Sprite2D.new()
	pulse.texture = AURA_RING_TEXTURE
	pulse.modulate = pulse_color
	pulse.scale = _get_aura_ring_scale(AURA_RING_START_RADIUS, texture_size)

	unit.add_child(pulse)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		pulse,
		"scale",
		_get_aura_ring_scale(heal_range, texture_size),
		AURA_RING_PULSE_DURATION
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, AURA_RING_PULSE_DURATION)
	tween.tween_callback(pulse.queue_free).set_delay(AURA_RING_PULSE_DURATION)

func _get_aura_ring_scale(radius: float, texture_size: Vector2) -> Vector2:
	return Vector2(radius * 2.0 / maxf(texture_size.x, 1.0), radius * 2.0 / maxf(texture_size.y, 1.0))

#override get_display_data to allow ui to show heal stats
func get_display_data() -> Dictionary:
	return {
		&"heal_amount": heal_amount,
		&"heal_interval": heal_interval,
		&"range": heal_range
	}
