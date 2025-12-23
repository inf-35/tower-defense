extends Behavior
class_name SunbeamBehavior

@export var max_targets: int = 3 ## Number of simultaneous lasers
@export var laser_width: float = 2.0
@export var laser_color: Color = Color.RED

var _active_lasers: Array[Line2D] = []
var _current_targets: Array[Unit] = []

func start() -> void:
	super.start()
	_initialize_laser_pool()

func update(delta: float) -> void:
	_cooldown += delta
	
	#acquire targets
	if is_instance_valid(range_component):
		_current_targets = range_component.get_targets(max_targets)

	_update_laser_visuals()
	_attempt_multi_attack()

func _initialize_laser_pool() -> void:
	for i in range(max_targets):
		var line = Line2D.new()
		line.width = laser_width
		line.default_color = laser_color
		line.visible = false
		# Improve visuals
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND

		if is_instance_valid(References.projectiles):
			References.projectiles.add_child(line)
			## move_to_back() ensures lasers appear under the tower sprite
			#graphics.move_child(line, 0) 
		else:
			unit.add_child(line)
			
		_active_lasers.append(line)

func _update_laser_visuals() -> void:
	var muzzle_pos := unit.global_position
	if is_instance_valid(attack_component) and is_instance_valid(attack_component.muzzle):
		muzzle_pos = attack_component.muzzle.position
	
	for i in range(max_targets):
		var line = _active_lasers[i]
		
		if i < _current_targets.size():
			var target = _current_targets[i]
			if is_instance_valid(target):
				line.visible = true
				line.clear_points()
				line.add_point(muzzle_pos)
				line.add_point(target.global_position)
			else:
				line.visible = false
		else:
			line.visible = false

func _attempt_multi_attack() -> void:
	if not _is_attack_possible_generic():
		return
		
	# attack all current targets
	for target in _current_targets:
		if is_instance_valid(target):
			attack_component.attack(target)
	
	_cooldown = 0.0

# Helper duplicating _is_attack_possible but checking list size instead of single target
func _is_attack_possible_generic() -> bool:
	if attack_component == null or range_component == null:
		return false
	if unit.disabled:
		return false
	if _current_targets.is_empty():
		return false
		
	if attack_component.current_cooldown <= 0.0:
		return true

	return false
