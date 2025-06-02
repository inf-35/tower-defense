extends Node #player

var health: int = 200

#blueprints

var blueprints: Array[Blueprint] = []

func has_blueprint(tower_type: Towers.Type) -> bool:
	var found: bool = false
	for blueprint: Blueprint in blueprints:
		if blueprint.tower_type == tower_type:
			found = true
			break

	return found
	
func consume_blueprint(tower_type: Towers.Type) -> bool:
	for blueprint: Blueprint in blueprints:
		if blueprint.tower_type == tower_type:
			blueprints.erase(blueprint)
			return true
			
	return false

#ready

func _ready():
	for i in 100:
		blueprints.append_array([
			Blueprint.new(Towers.Type.PALISADE),
			Blueprint.new(Towers.Type.SLOW_TOWER)
		])
		
	ClickHandler.click_on_island.connect(func(world_position: Vector2, tower_type: Towers.Type):
		if not has_blueprint(tower_type):
			print("no blueprint!")
			return
			
		consume_blueprint(tower_type)
		var cell: Vector2i = Island.position_to_cell(world_position)
		if Towers.tower_stats[tower_type].construct > Terrain.is_constructable(References.island.terrain_grid[cell]):
			return
		References.island.construct_tower(cell, tower_type)
	)
