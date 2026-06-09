extends Node #TargetingCoordinator

signal priority_target_changed(target: Unit)

var damage_reservations: Dictionary[Unit, float] = {}
var priority_target: Unit = null

func set_priority_target(target: Unit) -> void:
	if not _is_valid_priority_target(target):
		clear_priority_target()
		return

	if priority_target == target:
		return

	_disconnect_priority_target()
	priority_target = target
	if not target.tree_exiting.is_connected(_on_priority_target_exiting):
		target.tree_exiting.connect(_on_priority_target_exiting, CONNECT_ONE_SHOT)
	priority_target_changed.emit(priority_target)

func clear_priority_target() -> void:
	if priority_target == null:
		return

	_disconnect_priority_target()
	priority_target = null
	priority_target_changed.emit(null)

func get_priority_target() -> Unit:
	if not _is_valid_priority_target(priority_target):
		clear_priority_target()
		return null

	return priority_target

#records expected damage dealt to enemy, prevents two towers "overkilling" a unit.
func add_damage(unit: Variant, damage: float) -> void: ##its ok to pass a null target into this function
	if not is_instance_valid(unit):
		return

	if not damage_reservations.has(unit):
		damage_reservations[unit] = damage
	else:
		damage_reservations[unit] += damage

func clear_damage(unit) -> void:
	if not is_instance_valid(unit):
		return

	damage_reservations.erase(unit)

func is_unit_overkilled(unit: Unit) -> bool: #prevents overkill on units
	if not damage_reservations.has(unit):
		return false

	if not is_instance_valid(unit.health_component): #units without health component (bc they dont take damage) should always be ignored
		return true

	if damage_reservations[unit] >= unit.health_component.health:
		return true
	else:
		return false

func _ready() -> void:
	set_process(false)

func _on_priority_target_exiting() -> void:
	clear_priority_target()

func _disconnect_priority_target() -> void:
	if not is_instance_valid(priority_target):
		return

	if priority_target.is_queued_for_deletion():
		return

	if priority_target.tree_exiting.is_connected(_on_priority_target_exiting):
		priority_target.tree_exiting.disconnect(_on_priority_target_exiting)

func _is_valid_priority_target(target: Unit) -> bool:
	if not is_instance_valid(target):
		return false

	if target is Tower:
		return false

	if not target.hostile:
		return false

	if target.abstractive or target.incorporeal:
		return false

	if target.disabled:
		return false

	if not is_instance_valid(target.health_component):
		return false

	if target.health_component.health <= 0.0:
		return false

	return true
