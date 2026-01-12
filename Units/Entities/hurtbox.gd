extends Node2D
class_name Hurtbox

# the payload to deliver every tick
@export var attack_data: AttackData

@export var affiliations_hit:  int = 0b00 ##affiliations hit by this hurtbox (00 -> none, 01 -> hostiles only, 10 -> allies only)
@export var lifetime: float

var _area: Area2D
var _source_unit_ref: WeakRef # Optional: Track who created this for kill credit

var _targets_in_area: Array[Unit]

func setup(pos: Vector2, source: Unit) -> void:
	position = pos
	_source_unit_ref = weakref(source)
	
	_area = Area2D.new()
	_area.monitorable = false
	_area.monitoring = true

	_area.collision_mask = affiliations_hit
	_area.collision_layer = 0
	
	_area.area_entered.connect(_on_area_entered)
	_area.area_exited.connect(_on_area_exited)
	
	var shape = CircleShape2D.new()
	shape.radius = attack_data.radius
	
	var coll = CollisionShape2D.new()
	coll.shape = shape
	_area.add_child(coll)
	add_child(_area)

	var life_timer = Clock.create_game_timer(lifetime)
	life_timer.timeout.connect(_on_death)

var _cooldown: float = 0.0
func _process(_d: float):
	_cooldown += Clock.game_delta
	if _cooldown > attack_data.cooldown:
		_on_damage_tick()
		_cooldown = 0.0

func _on_area_entered(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		if not _targets_in_area.has(area.unit):
			_targets_in_area.append(area.unit)

func _on_area_exited(area: Node2D) -> void:
	if area is Hitbox and is_instance_valid(area.unit):
		_targets_in_area.erase(area.unit)

func _on_damage_tick() -> void:
	if _targets_in_area.is_empty() or not attack_data:
		return
		
	# apply damage to all valid targets currently inside the laser
	for i: int in range(_targets_in_area.size() - 1, -1, -1): # traverse backwards through array
		var target: Unit = _targets_in_area[i]
		if not is_instance_valid(target):
			_targets_in_area.remove_at(i)
			continue
			
		var hit_copy: HitData = attack_data.generate_generic_hit_data()
		hit_copy.target = target
		# the laser has no single source, so we can leave it null
		hit_copy.source = _source_unit_ref.get_ref() if _source_unit_ref else null
		
		# use a simple hitscan delivery
		var delivery_data := DeliveryData.new()
		delivery_data.delivery_method = DeliveryData.DeliveryMethod.HITSCAN
		delivery_data.use_source_position_override = true
		delivery_data.source_position = global_position
		
		CombatManager.resolve_hit(hit_copy, delivery_data)

func _on_death() -> void:
	queue_free()
