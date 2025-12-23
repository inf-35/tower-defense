extends Behavior
class_name AcceleratingBehavior

@export var speed_increase_percent: float = 0.10 ## +N% speed per interval
@export var interval: float = 1.0 ## how often to apply the boost (seconds)
@export var max_bonus: float = -1.0 ## cap (negative = no cap)

var _timer: float = 0.0
var _current_bonus: float = 0.0
var _speed_modifier: Modifier

func start() -> void:
	super.start()

	_speed_modifier = Modifier.new(Attributes.id.MAX_SPEED, 1.0, 0.0, -1.0)
	modifiers_component.add_modifier(_speed_modifier)
	
func detach():
	if is_instance_valid(_speed_modifier) and is_instance_valid(modifiers_component):
		modifiers_component.remove_modifier(_speed_modifier)

func update(delta: float) -> void:
	super.update(delta) # keeps the unit moving/attacking
	
	_timer += delta
	if _timer >= interval:
		_timer = 0.0
		_apply_acceleration()

func _apply_acceleration() -> void:
	# cap the speed
	if max_bonus > 0.0 and _current_bonus >= max_bonus:
		return
		
	_current_bonus += speed_increase_percent
	_speed_modifier.multiplicative = 1.0 + _current_bonus
	#notify modifier component that modifier is changed
	modifiers_component.change_modifier(_speed_modifier)
