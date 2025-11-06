# adjacency_boost_effect.gd
extends GlobalEffect
class_name AdjacencyBoostEffect

@export var _modifier_prototype: ModifierDataPrototype ##this modifier is applied per satisfying adjacent tower
# we track which towers are currently being buffed and the modifier we applied
var _buffed_towers: Dictionary[Tower, Modifier] = {}

# called by the GlobalModifierService when this relic is acquired
func initialise() -> void:
	# for this specific relic, the modifier is defined on the scene, not the relic data
	# this is a design choice; you could also have it read from the relic_data
	# connect to the island's signal to know when new towers are built
	References.island.tower_changed.connect(func(cell: Vector2i):
		_evaluate_tower_at(cell) # evaluate tower that is being modified
		for adjacency: Vector2i in Navigation.DIRECTIONS:
			_evaluate_tower_at(cell + adjacency) # and also evaluate neighbouring towers
	)
	
	# evaluate all existing towers immediately
	for cell: Vector2i in References.island.tower_grid.keys():
		_evaluate_tower_at(cell)

# called when a specific tower's neighbors change
func _evaluate_tower_at(cell: Vector2i) -> void:
	var island: Island = References.island
	
	if not island.tower_grid.has(cell):
		return
		
	var tower: Tower = island.tower_grid[cell]
	var adjacent_towers: int = References.island.get_adjacent_towers(cell).size()
	var is_buffed: bool = _buffed_towers.has(tower)

	# logic: apply buff if adjacent and not already buffed
	if adjacent_towers > 0 and not is_buffed:
		print("Adjacent relic applied")
		var new_modifier := _modifier_prototype.generate_modifier()
		tower.modifiers_component.add_modifier(new_modifier)
		_buffed_towers[tower] = new_modifier

	# logic: remove buff if not adjacent and currently buffed
	elif adjacent_towers == 0 and is_buffed:
		print("Adjacent relic removed")
		var modifier_to_remove: Modifier = _buffed_towers[tower]
		tower.modifiers_component.remove_modifier(modifier_to_remove)
		_buffed_towers.erase(tower)
