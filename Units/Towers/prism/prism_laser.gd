# prism_laser.gd
extends Area2D
class_name PrismLaser

# --- external configuration ---
@export var collision_shape: CollisionShape2D
@export var _damage_timer: Timer

# --- configuration ---
var hit_data_prototype: HitData # set by the prismtowerbehavior
var cooldown: float ##time between hits, set by prismtowerbehavior
var prism_a: Tower #two prisms form a pair producing a laser
var prism_b: Tower

# --- state ---
var _targets_in_area: Array[Unit] = []

func _ready() -> void:
	# configure the area to detect enemies
	self.collision_layer = 0
	self.collision_mask = Hitbox.get_mask(not prism_a.hostile) # lasers hit enemies (hostile)
	self.monitoring = true
	self.monitorable = false

	_damage_timer.wait_time = cooldown
	_damage_timer.timeout.connect(_on_damage_tick)
	_damage_timer.start()
	
	self.area_entered.connect(_on_area_entered)
	self.area_exited.connect(_on_area_exited)

func _on_area_entered(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		if not _targets_in_area.has(area.unit):
			_targets_in_area.append(area.unit)

func _on_area_exited(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		_targets_in_area.erase(area.unit)

func _on_damage_tick() -> void:
	if _targets_in_area.is_empty() or not is_instance_valid(hit_data_prototype):
		return
		
	# apply damage to all valid targets currently inside the laser
	for i: int in range(_targets_in_area.size() - 1, -1, -1): # traverse backwards through array
		var target: Unit = _targets_in_area[i]
		if not is_instance_valid(target):
			_targets_in_area.remove_at(i)
			continue
			
		var hit_copy: HitData = hit_data_prototype.duplicate()
		hit_copy.target = target
		# the laser has no single source, so we can leave it null
		hit_copy.source = prism_a if randf() > 0.5 else prism_b
		
		# use a simple hitscan delivery
		var delivery_data := DeliveryData.new()
		delivery_data.delivery_method = DeliveryData.DeliveryMethod.HITSCAN
		
		CombatManager.resolve_hit(hit_copy, delivery_data)
