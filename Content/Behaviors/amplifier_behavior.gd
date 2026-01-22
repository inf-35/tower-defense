# amplifier_behavior.gd
extends Behavior
class_name AmplifierBehavior

# --- configuration ---
# assign a ModifierDataPrototype resource in the inspector to define the buff this amplifier provides.
@export var modifier_prototypes: Array[ModifierDataPrototype] ##modifier that will be applied to adjacent towers (per adjacent amplifier)

# --- private state ---
# this dictionary tracks the modifiers this specific amplifier has applied to other towers.
# format: { Tower -> Array[Modifier] }
var _applied_modifiers: Dictionary[Tower, Array] = {}

func detach():
	# revoke our contribution from all current neighbors
	for t in _applied_modifiers:
		_remove_modifier_from_tower(t)
		
func attach():
	_on_adjacency_updated(unit.get_adjacent_towers())

# called by the unit chassis after all components are ready.
func start() -> void:
	# this behavior only makes sense on a tower.
	if not unit is Tower:
		push_warning("AmplifierBehavior can only be used on a Tower.")
		set_process(false) # disable this behavior
		return
	
	# connect to the host tower's signal to know when its neighbors change.
	var tower: Tower = unit as Tower
	if not tower.adjacency_updated.is_connected(_on_adjacency_updated):
		tower.adjacency_updated.connect(_on_adjacency_updated)
	
	# perform an initial check in case the tower is spawned next to existing towers.
	# we need to wait a frame for the island to settle its adjacency calculations.
	attach()

# this is the main logic, triggered whenever the host tower's neighbors change.
func _on_adjacency_updated(new_adjacencies: Dictionary[Vector2i, Tower]) -> void:
	# fail gracefully if no modifier is defined for this amplifier.
	if modifier_prototypes.is_empty():
		_clear_all_modifiers() # clear any existing effects and stop
		return

	var current_adjacent_towers: Array[Tower] = new_adjacencies.values()
	
	# --- 1. remove modifiers from towers that are no longer adjacent ---
	var towers_to_unmodify: Array[Tower]
	for affected_tower: Tower in _applied_modifiers:
		if not current_adjacent_towers.has(affected_tower):
			towers_to_unmodify.append(affected_tower)
	
	for tower: Tower in towers_to_unmodify:
		_remove_modifier_from_tower(tower)

	# --- 2. apply modifiers to newly adjacent towers ---
	for tower: Tower in current_adjacent_towers:
		if (not _applied_modifiers.has(tower)) or _applied_modifiers[tower].is_empty():
			_apply_modifier_to_tower(tower)

# this is the canonical cleanup function, called automatically when the tower is destroyed.
func _exit_tree() -> void:
	_clear_all_modifiers()

# --- private helper functions ---

func _apply_modifier_to_tower(target_tower: Tower) -> void:
	if not is_instance_valid(target_tower) or not is_instance_valid(target_tower.modifiers_component):
		return
	
	for modifier_prototype: ModifierDataPrototype in modifier_prototypes:
		var new_modifier := modifier_prototype.generate_modifier()
		# brand the modifier with our host unit's ID for clear source tracking.
		new_modifier.source_id = unit.unit_id
		
		target_tower.modifiers_component.add_modifier(new_modifier)
		if not _applied_modifiers.has(target_tower):
			_applied_modifiers[target_tower] = []
		_applied_modifiers[target_tower].append(new_modifier) # track the applied modifier

func _remove_modifier_from_tower(target_tower: Tower) -> void:
	if not _applied_modifiers.has(target_tower):
		return
		
	if is_instance_valid(target_tower) and is_instance_valid(target_tower.modifiers_component):
		var modifiers_to_remove: Array = _applied_modifiers[target_tower]
		for modifier_to_remove: Modifier in modifiers_to_remove:
			target_tower.modifiers_component.remove_modifier(modifier_to_remove)
	
	_applied_modifiers.erase(target_tower)

func _clear_all_modifiers() -> void:
	# create a copy of the keys because we will be modifying the dictionary while iterating
	var towers_to_clear: Array[Tower] = _applied_modifiers.keys()
	for tower: Tower in towers_to_clear:
		_remove_modifier_from_tower(tower)

func draw_visuals(canvas: RangeIndicator) -> void:
	var tower := unit as Tower
	if not is_instance_valid(tower): return
	
	var margin: int = 2
	var cell_size := Island.CELL_SIZE - margin
	var half_size := Vector2(cell_size, cell_size) * 0.5

	var adj_cells: Array[Vector2i] = tower.get_adjacent_cells()
	
	for cell: Vector2i in adj_cells:
		var pos = Island.cell_to_position(cell)
		var rect = Rect2(pos - half_size, Vector2(cell_size, cell_size))

		canvas.draw_rect(rect, canvas.highlight_color, false, 1.0)
