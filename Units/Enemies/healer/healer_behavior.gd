extends Behavior
class_name HealerBehavior

# --- configuration ---
@export var heal_amount: float = 0.0 ##amount of hp points
@export var heal_interval: float = 3.0 ##interval (in seconds) between heals
@export var heal_range: float = 10.0

# --- state ---
var _heal_area: Area2D
var _allies_in_range: Array[Unit] = []

func start() -> void:
	super.start()
	_setup_ally_detection()
	# healers move towards the objective like normal units
	_attempt_navigate_to_origin()

func detach():
	if is_instance_valid(_heal_area):
		_heal_area.free()

func update(_delta: float) -> void:
	# update the cooldown timer
	_cooldown += Clock.game_delta
	
	# 1. attempt to heal if off cooldown
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
	
	_heal_area.area_entered.connect(_on_ally_entered)
	_heal_area.area_exited.connect(_on_ally_exited)

func _on_ally_entered(area: Area2D) -> void:
	# Ensure we are detecting a Unit's Hitbox
	if not area is Hitbox:
		return
	
	var ally_unit: Unit = area.unit
	if not is_instance_valid(ally_unit):
		return
		
	# Optional: Don't heal self
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
	
	# 1. prune invalid instances (dead units)
	# this uses a custom filter to remove null/freed instances efficiently
	var valid_allies: Array[Unit] = []
	for ally in _allies_in_range:
		if is_instance_valid(ally) and is_instance_valid(ally.health_component):
			valid_allies.append(ally)
	_allies_in_range = valid_allies
	
	# 2. apply Heal
	for ally: Unit in _allies_in_range:
		var health_comp: HealthComponent = ally.health_component
	
		# the health setter in HealthComponent automatically clamps to max_health
		health_comp.health += heal_amount
		did_heal_anyone = true
		_spawn_heal_vfx(ally)

	# 3. Visual Feedback for the Healer itself
	if did_heal_anyone:
		_play_animation(&"cast") # Assuming an animation exists
		_spawn_pulse_vfx()
		
	# Return true to reset cooldown, even if we didn't heal anyone?
	# Usually yes, to maintain the rhythm, or false to heal immediately when someone gets hurt.
	# Here we return true only if we acted, or strictly strictly adhere to interval.
	# Let's strictly adhere to interval to prevent spam-checking.
	return true 

# --- Visuals ---

func _spawn_heal_vfx(target: Unit) -> void:
	# Simple flash effect using the existing shader setup on units
	if is_instance_valid(target.graphics) and target.graphics.material is ShaderMaterial:
		# Fallback: Simple tween scale bounce
		var tween = create_tween()
		tween.tween_property(target, "scale", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(target, "scale", Vector2(1.0, 1.0), 0.1)

func _spawn_pulse_vfx() -> void:
	# Create a temporary expanding circle to visualize the aura
	if not is_instance_valid(unit): return
	
	var pulse = Line2D.new()
	pulse.width = 2.0
	pulse.default_color = Color(0.2, 1.0, 0.4, 0.8)
	pulse.closed = true
	
	# Generate circle points
	var points: PackedVector2Array = []
	var steps = 16
	for i in range(steps):
		var angle = (float(i) / steps) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * 10.0) # Start small
	pulse.points = points
	
	unit.add_child(pulse)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2.ONE * (heal_range / 10.0), 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.5)
	tween.tween_callback(pulse.queue_free).set_delay(0.5)

# override get_display_data to allow UI to show heal stats
func get_display_data() -> Dictionary:
	return {
		&"heal_amount": heal_amount,
		&"heal_interval": heal_interval,
		&"range": heal_range
	}
