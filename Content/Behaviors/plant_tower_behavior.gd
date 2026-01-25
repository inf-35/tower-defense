# plant_tower_behavior.gd
extends DefaultTowerBehavior
class_name PlantTowerBehavior

# --- configuration (designer-friendly) ---
@export_category("Growth")
@export var additive_damage_per_wave: float = 0.0
@export var multiplicative_damage_per_wave: float = 0.0

# --- state ---
var _current_bonus_damage: float = 0.0
var _current_bonus_multiplicative_damage: float = 0.0:
	set(nec):
		_current_bonus_multiplicative_damage = nec
var _growth_modifier: Modifier = null

# this function is called by the unit's initialize() method
func start() -> void:
	# connect to the global signal that announces a new wave cycle
	Phases.wave_ended.connect(_on_wave_cycle_started)
	# apply the initial state (which is no bonus damage)
	attach()

func attach():
	_apply_damage_modifier()
	
func transfer_state(untyped_new_behavior: Behavior):
	var new_behavior := untyped_new_behavior as PlantTowerBehavior
	new_behavior._current_bonus_damage = _current_bonus_damage
	new_behavior._current_bonus_multiplicative_damage = _current_bonus_multiplicative_damage
	new_behavior._apply_damage_modifier()

# this is the core logic, triggered once per wave
func _on_wave_cycle_started(_wave_number: int) -> void:
	# do nothing if the tower is disabled
	if not is_instance_valid(unit) or unit.disabled:
		return
		
	# increase the bonus and re-apply the modifier
	_current_bonus_damage += additive_damage_per_wave
	_current_bonus_multiplicative_damage += multiplicative_damage_per_wave
	_apply_damage_modifier()

# this helper function manages the modifier on the tower
func _apply_damage_modifier() -> void:
	if not is_instance_valid(modifiers_component):
		return

	# create a new modifier with the updated bonus damage
	var new_modifier := Modifier.new(Attributes.id.DAMAGE)
	new_modifier.additive = _current_bonus_damage
	new_modifier.multiplicative = 1.0 + _current_bonus_multiplicative_damage
	new_modifier.cooldown = -1.0
	modifiers_component.replace_modifier(_growth_modifier, new_modifier)
	
	# store the new modifier so we can replace it next wave
	_growth_modifier = new_modifier

# this behavior uses the standard attack logic in the unit's _process loop
# so no custom update loop

func get_save_data() -> Dictionary:
	return {
		"additive_damage_per_wave": additive_damage_per_wave,
		"multiplicative_damage_per_wave": multiplicative_damage_per_wave,
		"current_bonus_damage": _current_bonus_damage,
		"current_bonus_multiplicative_damage": _current_bonus_multiplicative_damage,
	}

func load_save_data(save_data: Dictionary) -> void:
	additive_damage_per_wave = save_data.additive_damage_per_wave
	multiplicative_damage_per_wave = save_data.multiplicative_damage_per_wave
	_current_bonus_damage = save_data.current_bonus_damage
	_current_bonus_multiplicative_damage = save_data.current_bonus_multiplicative_damage
	
	attach()
	
