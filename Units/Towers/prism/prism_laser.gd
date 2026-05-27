# prism_laser.gd
extends Area2D
class_name PrismLaser

# --- external configuration ---
@export var collision_shape: CollisionShape2D
@export var color_start: Color = Color(1.0, 0.8, 0.2, 0.424) ## Base color (e.g. Yellow)
@export var color_end: Color = Color(1.0, 0.8, 0.2, 1.0)  ## Peak color (e.g. Red/Orange)
@export var pulse_speed: float = 5.0 ## How fast the laser pulses

# --- configuration ---
var prism_a: Tower #two prisms form a pair producing a laser
var prism_b: Tower

# --- state ---
var _targets_in_area: Array[Unit] = []
var _time_passed: float = 0.0

func _ready() -> void:
	# configure the area to detect enemies
	self.collision_layer = 0
	self.collision_mask = Hitbox.get_mask(not prism_a.hostile) # lasers hit enemies (hostile)
	self.monitoring = true
	self.monitorable = false
	self.z_index = Layers.ALLIED_PROJECTILES
	
	self.area_entered.connect(_on_area_entered)
	self.area_exited.connect(_on_area_exited)
	
func _process(delta: float) -> void:
	# Update the timer for the sine wave calculation
	_time_passed += delta
	# Request a redraw every frame so the color animates
	queue_redraw()

func _on_area_entered(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		if not _targets_in_area.has(area.unit):
			_targets_in_area.append(area.unit)

func _on_area_exited(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		_targets_in_area.erase(area.unit)

func damage_tick() -> void:
	if _targets_in_area.is_empty(): return

	# apply damage to all valid targets currently inside the laser
	for i: int in range(_targets_in_area.size() - 1, -1, -1): # traverse backwards through array
		var target: Unit = _targets_in_area[i]
		if not is_instance_valid(target):
			_targets_in_area.remove_at(i)
			continue
			
		var hit_copy: HitData = prism_a.attack_component.generate_hit_data()
		hit_copy.target = target
		# choose between two random sourcees
		hit_copy.source = prism_a if randf() > 0.5 else prism_b
		
		# use a simple hitscan delivery
		var delivery_data := DeliveryData.new()
		delivery_data.delivery_method = DeliveryData.DeliveryMethod.HITSCAN
		
		CombatManager.resolve_hit(hit_copy, delivery_data)
		
func _draw() -> void:
	if not is_instance_valid(collision_shape) or not collision_shape.shape is RectangleShape2D:
		return
		
	var rect_shape = collision_shape.shape as RectangleShape2D
	
	# The Area2D is centered exactly between the two prisms.
	# To draw a rect centered on this point, we offset by half the size.
	var rect = Rect2(-rect_shape.size / 2.0, rect_shape.size)
	
	# Calculate pulsing color
	# sin() returns -1 to 1. We remap it to 0 to 1.
	var t = (sin(_time_passed * pulse_speed) + 1.0) / 2.0
	var current_color = color_start.lerp(color_end, t)
	
	# Draw the filled rectangle representing the beam
	draw_rect(rect, current_color, true)
