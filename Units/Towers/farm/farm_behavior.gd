extends Behavior
class_name FarmBehavior

@export var income_per_wave: float = 1.5

static func _static_init() -> void:
	ModifiersComponent.register_dynamic_attribute(&"farm_income_per_wave")

func display_start() -> void:
	_register_income_stats()

func start() -> void:
	_register_income_stats()
	Run.phases.wave_ended.connect(_on_wave_ended)

func _register_income_stats() -> void:
	unit.modifiers_component.register_dynamic_stat(&"farm_income_per_wave", income_per_wave)

func check_placement_validity(island: Island, cell: Vector2i, facing: int) -> Dictionary:
	var neighbors := (unit as Tower).get_adjacent_cells()
	#check for any structure
	for n: Vector2i in neighbors:
		if island.get_tower_on_tile(n) != null:
			return { "valid": true, "error": "" }

	return { "valid": false, "error": "Must touch a Structure" }

func _on_wave_ended(_wave: int) -> void:
	if (unit as Tower).current_state != Tower.State.ACTIVE:
		return

	var total: float = unit.modifiers_component.pull_dynamic_stat(&"farm_income_per_wave")

	Run.player.flux += total

	if is_instance_valid(UI.floating_text_manager):
		UI.floating_text_manager.show_text("+%.2f" % total, unit.global_position, Color.GOLD)

func get_display_data() -> Dictionary:
	return {
		"income": income_per_wave
	}
