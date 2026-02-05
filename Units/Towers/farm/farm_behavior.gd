extends Behavior
class_name FarmBehavior

@export var income_per_wave: float = 1.0
@export var adjacent_bonus: float = 0 ## extra income per adjacent tower

static func _static_init() -> void:
	ModifiersComponent.register_dynamic_attribute(&"farm_income_per_wave")
	ModifiersComponent.register_dynamic_attribute(&"farm_adjacent_bonus")

func start() -> void:
	unit.modifiers_component.register_dynamic_stat(&"farm_income_per_wave", income_per_wave)
	unit.modifiers_component.register_dynamic_stat(&"farm_adjacent_bonus", adjacent_bonus)
	Phases.wave_ended.connect(_on_wave_ended)

func check_placement_validity(island: Island, cell: Vector2i, facing: int) -> Dictionary:
	var neighbors := (unit as Tower).get_adjacent_cells()
	#check for any structure
	for n: Vector2i in neighbors:
		if island.get_tower_on_tile(n) != null:
			return { "valid": true, "error": "" }
			
	return { "valid": false, "error": "Must touch a Structure" }

# --- Gameplay Logic ---
func _on_wave_ended(_wave: int) -> void:
	if (unit as Tower).current_state != Tower.State.ACTIVE:
		return
	
	var total = unit.modifiers_component.pull_dynamic_stat(&"farm_income_per_wave")
	
	var adj_count: int = 0
	for tower: Tower in (unit as Tower).get_adjacent_towers().values():
		if tower.type == Towers.Type.FARM:
			adj_count += 1
	total += adj_count * unit.modifiers_component.pull_dynamic_stat(&"farm_adjacent_bonus")
	
	Player.flux += total
	print(total)
	
	if is_instance_valid(UI.floating_text_manager):
		UI.floating_text_manager.show_text("+%.2f" % total, unit.global_position, Color.GOLD)

func get_display_data() -> Dictionary:
	return {
		"income": income_per_wave,
		"bonus": adjacent_bonus
	}
