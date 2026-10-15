extends Behavior
class_name FarmBehavior

const FARM_INCOME_KEY: StringName = &"farm_income_per_wave"

@export var income_per_wave: float = 0.8 ##base gold earned each wave before farm-neighbor bonuses and relic modifiers
@export var adjacent_farm_income_bonus: float = 0.4 ##additional base gold earned for each adjacent active farm
@export_range(1.0, 8.0, 0.25) var payout_text_lifetime_multiplier: float = 4.0 ##display-time multiplier that keeps the dawn gold payout readable

static func _static_init() -> void:
	ModifiersComponent.register_dynamic_attribute(FARM_INCOME_KEY)

func display_start() -> void:
	_register_income_stats()

func start() -> void: ##connects farm income to wave payout and island changes so adjacency income stays live
	attach()
	if not Run.phases.wave_ended.is_connected(_on_wave_ended):
		Run.phases.wave_ended.connect(_on_wave_ended)

func attach() -> void: ##refreshes income and listens for farm adjacency changes while this farm is active
	_connect_island_changed()
	_register_income_stats()

func detach() -> void: ##stops adjacency refreshes while this farm is ruined or otherwise inactive
	_disconnect_island_changed()

func _connect_island_changed() -> void: ##subscribes to the island-wide structural invalidation signal used by nearby farm income
	var island: Island = Run.references.island if is_instance_valid(Run.references.island) else null
	if not is_instance_valid(island):
		return
	if island.island_changed.is_connected(_register_income_stats):
		return
	island.island_changed.connect(_register_income_stats)

func _disconnect_island_changed() -> void: ##disconnects the live adjacency refresh hook without assuming the island still exists
	var island: Island = Run.references.island if is_instance_valid(Run.references.island) else null
	if not is_instance_valid(island):
		return
	if not island.island_changed.is_connected(_register_income_stats):
		return
	island.island_changed.disconnect(_register_income_stats)

func _register_income_stats() -> void: ##sets the farm income base to 0.8 plus 0.4 per adjacent active farm
	var adjacent_farm_count: int = _get_adjacent_farm_count()
	var base_income: float = income_per_wave + adjacent_farm_income_bonus * adjacent_farm_count
	unit.modifiers_component.register_dynamic_stat(FARM_INCOME_KEY, base_income)

func _get_adjacent_farm_count() -> int: ##counts unique adjacent active farms so multi-cell neighbors cannot double count
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower):
		return 0
	if not is_instance_valid(Run.references.island):
		return 0

	var seen_farms: Dictionary[int, bool] = {}
	for neighbor: Tower in tower.get_adjacent_towers().values():
		if not is_instance_valid(neighbor):
			continue
		if neighbor.type != Towers.Type.FARM:
			continue
		if neighbor.current_state != Tower.State.ACTIVE:
			continue
		seen_farms[neighbor.unit_id] = true

	return seen_farms.size()

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

	var total: float = unit.modifiers_component.pull_dynamic_stat(FARM_INCOME_KEY)

	Run.player.flux += total

	if is_instance_valid(UI.floating_text_manager):
		var popup_lifetime: float = UI.floating_text_manager.default_lifetime * payout_text_lifetime_multiplier
		UI.floating_text_manager.show_ink_outlined_text("+%.2f" % total, unit.global_position, Color.GOLD, false, popup_lifetime)

func get_display_data() -> Dictionary: ##reports the authored base income value for inspector/tooltip formatting
	return {
		"income": income_per_wave
	}
