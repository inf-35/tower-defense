extends Node #(Units)
#repository of units, and their associated info
enum Type {
	BASIC,
	BUFF,
	DRIFTER,
	ARCHER,
	TROLL,
	WARRIOR,
	HEALER,
	SPRINTER,
	SPRINTER_PLUS,
	PROTECTOR,
	FLESHBLOB,
	FLESHLET,
	PHANTOM,
	EFFIGY,
	SUMMONER,
	ZOMBIE,
	GIANT,
	GIANT_PLUS,
	HULK,
	HULK_PLUS,
	TROLL_PLUS,
	WARRIOR_PLUS,
	CLERIC,
	HEALER_PLUS,
	OLIPHANT
}

var unit_stats: Dictionary[Type, UnitData] = {}
var unit_prototypes: Dictionary[Type, Unit] = {}

const VERBOSE: bool = false
const GLOBAL_ENEMY_HP_MULTIPLIER: float = 1.25
const ENEMY_HP_PER_WAVE_MULTIPLIER: float = 0.01
const GLOBAL_ENEMY_SPEED_MULTIPLIER: float = 1/1.25
const GLOBAL_ENEMY_DAMAGE_MULTIPLIER: float = 1.0
const MIN_ENEMY_PRESENTATION_SCALE: float = 0.8
const MAX_ENEMY_PRESENTATION_SCALE: float = 0.9
const SMALL_ENEMY_VISUAL_EXTENT: float = 6.0
const LARGE_ENEMY_VISUAL_EXTENT: float = 11.6

func start() -> void:
	unit_stats.clear()
	unit_prototypes.clear()
	#dont clear units modified by difficulty, as unitdatas are persistent
	_load_all_unit_stats()

func get_unit_prototype(unit_type: Type) -> Unit:
	if (not unit_prototypes.has(unit_type)) or (not is_instance_valid(unit_prototypes[unit_type])): #if no prototype
		unit_prototypes[unit_type] = create_unit(unit_type) #create prototypical unit
		unit_prototypes[unit_type].abstractive = true #disable all effects and events
		unit_prototypes[unit_type].visible = false
		add_child(unit_prototypes[unit_type]) #trigger _ready() calls

		unit_prototypes[unit_type].position = Vector2(-2047 * unit_type * unit_prototypes[unit_type].unit_id, -4210 * unit_type * unit_prototypes[unit_type].unit_id) #somewhere extremely far away

		#these prototype units provide a "default" baseline to lookup from.
	return unit_prototypes[unit_type]

func get_unit_name(unit: Type) -> String:
	return unit_stats[unit].title

func get_unit_icon(unit: Type) -> Texture2D:
	return unit_stats[unit].icon

func get_unit_description(unit: Type) -> String:
	return unit_stats[unit].description

func get_stat_displays(unit: Type) -> Array[StatDisplayInfo]:
	return unit_stats[unit].stat_displays

func get_unit_flux(unit: Type) -> float:
	return unit_stats[unit].flux_value * 1.5

func get_unit_strength(unit: Type) -> float:
	return unit_stats[unit].strength_value

func get_unit_scene(unit: Type) -> PackedScene:
	return unit_stats[unit].unit_scene

func get_unit_route_mode(unit_type: Type) -> NavigationComponent.RouteMode: ##reads the unit's authored navigation route mode from its prototype navigation component
	var prototype: Unit = get_unit_prototype(unit_type)
	if not is_instance_valid(prototype.navigation_component):
		return NavigationComponent.RouteMode.DIRECT_TO_GOAL
	return prototype.navigation_component.route_mode

func get_unit_ignore_walls(unit_type: Type) -> bool: ##reads whether the unit's authored navigation component ignores walls for route rendering and spawning previews
	var prototype: Unit = get_unit_prototype(unit_type)
	if not is_instance_valid(prototype.navigation_component):
		return false
	return prototype.navigation_component.ignore_walls

func get_enemy_presentation_scale(graphics: Sprite2D) -> float: ##maps the authored sprite footprint smoothly from the small-enemy test scale to full-sized large enemies
	if not is_instance_valid(graphics):
		return 1.0

	var authored_size: Vector2 = graphics.get_rect().size.abs() * graphics.scale.abs()
	if is_zero_approx(authored_size.x) or is_zero_approx(authored_size.y):
		return 1.0

	var visual_extent: float = sqrt(authored_size.x * authored_size.y)
	var size_class: float = sqrt(smoothstep(SMALL_ENEMY_VISUAL_EXTENT, LARGE_ENEMY_VISUAL_EXTENT, visual_extent))
	return lerpf(MIN_ENEMY_PRESENTATION_SCALE, MAX_ENEMY_PRESENTATION_SCALE, size_class)

func create_unit(unit_type: Type) -> Unit:
	var _unit: Unit = get_unit_scene(unit_type).instantiate()
	_unit.flux_value = get_unit_flux(unit_type)
	_unit.strength = get_unit_strength(unit_type)
	_unit.enemy_type = unit_type
	if unit_stats[unit_type].important:
		_unit.set_meta(ID.UnitMeta.IS_IMPORTANT, true)

	_unit.ready.connect(func():
		if not is_instance_valid(_unit.modifiers_component):
			return
		if _unit.health_component:
			var global_hp_mod := Modifier.new(Attributes.id.MAX_HEALTH, _get_enemy_hp_multiplier_for_current_wave(), 0.0, -1.0)
			_unit.modifiers_component.add_permanent_modifier(global_hp_mod)
			_unit.health_component.health = _unit.get_stat(Attributes.id.MAX_HEALTH)
		if _unit.movement_component:
			var global_speed_mod := Modifier.new(Attributes.id.MAX_SPEED, GLOBAL_ENEMY_SPEED_MULTIPLIER, 0.0, -1.0)
			_unit.modifiers_component.add_permanent_modifier(global_speed_mod)
		if _unit.attack_component:
			var global_damage_mod := Modifier.new(Attributes.id.DAMAGE, GLOBAL_ENEMY_DAMAGE_MULTIPLIER, 0.0, -1.0)
			_unit.modifiers_component.add_permanent_modifier(global_damage_mod)

		CONNECT_ONE_SHOT
	)

	if Run.current_game_difficulty == Run.GameDifficulty.NORMAL:
		#wait for the unit to enter the tree and call _ready()
		_unit.ready.connect(func():
			if not is_instance_valid(_unit.modifiers_component):
				return
			if _unit.health_component:
				var mod_hp = Modifier.new(Attributes.id.MAX_HEALTH, 0.8, 0.0, -1.0)
				_unit.modifiers_component.add_permanent_modifier(mod_hp)
				#force health to update to the new, lowered maximum
				_unit.health_component.health = _unit.health_component.health
			if _unit.movement_component:
				var mod_spd = Modifier.new(Attributes.id.MAX_SPEED, 0.8, 0.0, -1.0)
				_unit.modifiers_component.add_permanent_modifier(mod_spd),
			CONNECT_ONE_SHOT
		)
	return _unit

func _get_enemy_hp_multiplier_for_current_wave() -> float: ##applies the crude per-wave enemy hp growth on top of the global hp tuning
	var wave_number: int = Run.phases.current_wave_number if is_instance_valid(Run.phases) else 0
	return GLOBAL_ENEMY_HP_MULTIPLIER * (1.0 + float(wave_number) * ENEMY_HP_PER_WAVE_MULTIPLIER)

func _load_all_unit_stats() -> void:
	var base_directory: String = "res://Units/Enemies"

	var dir: DirAccess = DirAccess.open(base_directory)
	if not dir:
		push_error("Units: Failed to open base directory: " + base_directory)
		return

	print("Units: Starting load from " + base_directory)
	dir.list_dir_begin()
	var folder_name: String = dir.get_next()

	while folder_name != "":
		#check for directories (ignoring . and ..)
		if dir.current_is_dir() and not folder_name.begins_with("."):
			var sub_dir_path: String = base_directory + "/" + folder_name + "/"

			#construct expected resource path: e.g. res://units/enemies/archer/archer.tres
			#note: relies on folder name matching file name exactly
			var resource_path: String = sub_dir_path + folder_name + ".tres"

			#handle (web)export remapping (.remap extension)
			#check if the file exists directly or with the .remap suffix
			if FileAccess.file_exists(resource_path) or FileAccess.file_exists(resource_path + ".remap"):
				var data_resource = load(resource_path)

				if data_resource is UnitData:
					#map folder name to enum key (e.g. "archer" -> archer)
					var type_name: String = folder_name.to_upper()

					if Type.has(type_name):
						var type_enum: Type = Type[type_name]
						unit_stats[type_enum] = data_resource
						if VERBOSE: print("Units: Loaded " + type_name)
					else:
						push_warning("Units: Folder '" + folder_name + "' does not match any 'Units.Type' Enum.")
				else:
					push_error("Units: Failed to load valid UnitData at " + resource_path)
			else:
				push_warning("Units: No .tres found in " + sub_dir_path)
				pass

		folder_name = dir.get_next()

	dir.list_dir_end()
	print("Units: Load complete. Total units: ", unit_stats.size())
