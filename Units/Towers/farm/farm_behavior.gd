extends Behavior
class_name FarmBehavior

@export var income_per_wave: int = 25
@export var adjacent_bonus: int = 0 ## extra income per adjacent tower

func start() -> void:
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
	
	var total = income_per_wave
	
	# Calculate Adjacency Bonus
	var adj_count = (unit as Tower).get_adjacent_towers().size()
	total += adj_count * adjacent_bonus
	
	Player.flux += total
	
	if is_instance_valid(UI.floating_text_manager):
		UI.floating_text_manager.show_text("+%d" % total, unit.global_position, Color.GOLD)

func get_display_data() -> Dictionary:
	return {
		"income": income_per_wave,
		"bonus": adjacent_bonus
	}
