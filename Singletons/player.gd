extends Node #player

var flux: float = 20.0: #serves as both the player's base health and currency
	set(val):
		flux = val
		UI.update_flux.emit(flux)

#blueprints

var blueprints: Array[Blueprint] = []

func has_blueprint(tower_type: Towers.Type) -> bool:
	var found: bool = false
	for blueprint: Blueprint in blueprints:
		if blueprint.tower_type == tower_type:
			found = true
			break

	return found

func add_blueprint(blueprint: Blueprint) -> void:
	blueprints.append(blueprint)
	UI.update_blueprints.emit(blueprints)
	
func consume_blueprint(tower_type: Towers.Type) -> bool:
	for blueprint: Blueprint in blueprints:
		if blueprint.tower_type == tower_type:
			blueprints.erase(blueprint)
			UI.update_blueprints.emit(blueprints)
			return true

	return false

#player-side globals
var effect_prototypes: Array[EffectPrototype] = [] #allied units will base their effectinstances off these prototypes

#ready

func _ready():
	for i in 10:
		blueprints.append_array([
			Blueprint.new(Towers.Type.TURRET),
			Blueprint.new(Towers.Type.PALISADE),
			Blueprint.new(Towers.Type.CATALYST),
			Blueprint.new(Towers.Type.FROST_TOWER),
		])
	add_blueprint(Blueprint.new(Towers.Type.BLUEPRINT_HARVESTER))
		
	ClickHandler.click_on_island.connect(func(world_position: Vector2, tower_type: Towers.Type, tower_facing: Tower.Facing):
		if not has_blueprint(tower_type):
			print("no blueprint!")
			return
			
		if Player.flux < Towers.tower_stats[tower_type].flux_cost:
			print("no flux!")
			return
			
		var cell: Vector2i = Island.position_to_cell(world_position)
		
		if (not References.island.terrain_level_grid.has(cell)) or Towers.tower_stats[tower_type].construct > References.island.terrain_level_grid[cell]:
			print("incorrect terrain!")
			return
		
		consume_blueprint(tower_type)
		Player.flux -= Towers.tower_stats[tower_type].flux_cost
		References.island.construct_tower(cell, tower_type, tower_facing)
	)

func choose_terrain_expansion():
	pass
	#... (expand terrain function is References.island.expand_by_block(n)
