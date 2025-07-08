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
		
	ClickHandler.place_tower_requested.connect(request_tower_placement)
	
func request_tower_placement(tower_type : Towers.Type, cell : Vector2i, facing : Tower.Facing):
	if not has_blueprint(tower_type): 
		return #blueprint/curreny checks
		
	if Player.flux < Towers.get_tower_cost(tower_type):
		return
		
	if References.island.tower_grid.has(cell): #tower already exists there
		var host : Tower = References.island.tower_grid[cell]
		if host.type == tower_type: #upgrade existing tower (of same type)
			consume_blueprint(tower_type)
			Player.flux -= Towers.get_tower_cost(tower_type)
			host.level += 1
		return
	
	if (not References.island.terrain_level_grid.has(cell)) or Towers.get_tower_minimum_terrain(tower_type) > References.island.terrain_level_grid[cell]:
		return #terrain checks
	
	consume_blueprint(tower_type)
	Player.flux -= Towers.get_tower_cost(tower_type)
	References.island.construct_tower(cell, tower_type, facing)

func choose_terrain_expansion():
	pass
	#... (expand terrain function is References.island.expand_by_block(n)
