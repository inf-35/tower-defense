extends Node
class_name Behavior

#this will be the unit "chassis" that owns this behavior
var unit: Unit

#references to the unit's other components, injected by the unit itself
var modifiers_component: ModifiersComponent
var health_component: HealthComponent
var movement_component: MovementComponent
var navigation_component: NavigationComponent
var range_component: RangeComponent
var attack_component: AttackComponent
var animation_player: AnimationPlayer

var graphics: Node2D
var turret: Node2D
#generic "timer" variable
var _cooldown: float = 0.0 ##NOTE: this is not the attack cooldown, which can be found in AttackComponent

func initialise(host_unit: Unit) -> void: ##his function is called by the unit to give the behavior all the tools it needs
	set_process(false)

	self.unit = host_unit
	#safely get references
	self.modifiers_component = unit.modifiers_component
	self.health_component = unit.health_component
	self.movement_component = unit.movement_component
	self.navigation_component = unit.navigation_component
	self.range_component = unit.range_component
	self.attack_component = unit.attack_component
	self.animation_player = unit.animation_player

	self.graphics = unit.graphics
	if &"turret" in unit:
		self.turret = unit.turret

	if unit.abstractive:
		display_start()
		return

	start()

	unit.subscribe_event(GameEvent.EventType.WAVE_STARTED, _on_unit_wave_started_event)
	unit.subscribe_event(GameEvent.EventType.HIT_RECEIVED, _on_unit_hit_received_event)
	unit.subscribe_event(GameEvent.EventType.REPLACED, _on_unit_replaced_event)

func _on_unit_wave_started_event(_event: GameEvent) -> void: ##resets behavior timing when the routed combat wave begins
	_cooldown = 0.0

func _on_unit_hit_received_event(_event: GameEvent) -> void: ##plays the authored hit reaction only for routed incoming-hit events
	_play_animation(&"hit")

func _on_unit_replaced_event(event: GameEvent) -> void: ##hands behavior state to the replacement unit created by an upgrade
	var data: UnitReplacedData = event.data as UnitReplacedData
	if not is_instance_valid(data) or data.old_unit != unit:
		return
	if is_instance_valid(data.new_unit.behavior):
		transfer_state(data.new_unit.behavior)

func detach() -> void: ##function called when the unit wants to detach this behavior (i.e. upon death)
	pass

func attach() -> void: ##function called when the unit wants to reattach this handler (i.e. tower resurrection)
	pass

func transfer_state(new_behavior: Behavior) -> void: ##called when we want to transfer state to another behavior (i.e. upgrading)
	new_behavior._cooldown = _cooldown

func display_start() -> void: ##for prototypes (abstractive)
	pass

func start() -> void: ##behavior start function, called at the start of behavior when the unit is created or revived
	#by default units try to navigate to the origin
	_attempt_navigate_to_origin()

func update(delta: float) -> void: ##main update loop; delta is already game delta
	#this virtual function will be overridden by concrete behaviors
	_cooldown += delta
	_attempt_simple_attack()

#this virtual function is the new, generic entrypoint for the ui to query
#custom data from a behavior. concrete behaviors should override this.
func get_display_data() -> Dictionary:
	return {} #return an empty dictionary by default

func on_inspector_action(_action_key: StringName) -> void: ##optional hook for authored inspector custom actions like ruins search buttons
	pass

func draw_visuals(canvas: RangeIndicator) -> void: #see RangeIndicator
	var tower: Tower = unit as Tower
	_draw_allowed_terrain_visuals(canvas, tower)
	if not tower.get_stat(Attributes.id.RANGE):
		return
	canvas.preview_circle(tower.global_position, tower.get_stat(Attributes.id.RANGE), canvas.range_color, false, 1.0)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##virtual introspection surface shared by spatial indexing and selection rendering
	return []

func sync_tower_influences() -> void: ##atomically publishes this behavior's current introspection descriptors to the island index
	var service: TowerInfluenceService = _get_tower_influence_service()
	if service == null or not unit is Tower:
		return
	service.sync_influences(self, unit as Tower, get_tower_influences())

func clear_tower_influences() -> void: ##removes every relationship published by this behavior during detach or teardown
	var service: TowerInfluenceService = _get_tower_influence_service()
	if service != null:
		service.clear_owner(self)

func draw_tower_influences(canvas: RangeIndicator) -> void: ##renders the same descriptors used by indexing without requiring subclass draw methods to call super
	for influence: TowerInfluence in get_tower_influences():
		canvas.preview_tower_influence(influence)

func _get_tower_influence_service() -> TowerInfluenceService: ##resolves the run-scoped influence index without making behavior logic depend on preview ui lifetime
	if not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return null
	return Run.references.island.influence_service

func _get_report_cells(report: TowerTopologyService.Report) -> Array[Vector2i]: ##normalizes topology report values into the typed cells expected by influence descriptors
	var cells: Array[Vector2i] = []
	if report != null:
		cells.assign(report.cells.values())
	return cells

func _draw_allowed_terrain_visuals(canvas: RangeIndicator, tower: Tower) -> void: ##highlights authored allowed-terrain cells for preview prototypes, even when those cells are already occupied
	if not is_instance_valid(tower) or not tower.abstractive:
		return

	var allowed_terrains: Array[Terrain.Base] = Towers.get_tower_allowed_terrains(tower.type)
	if allowed_terrains.is_empty():
		return

	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return

	for cell: Vector2i in island.terrain_base_grid:
		if not allowed_terrains.has(island.get_terrain_base(cell)):
			continue
		canvas.draw_cell(cell, canvas.highlight_color)

func draw_visuals_adjacent_tiles(canvas: RangeIndicator) -> void:
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower): return

	var margin: int = 2
	var cell_size := Island.CELL_SIZE - margin
	var half_size: Vector2 = Vector2(cell_size, cell_size) * 0.5

	var adj_cells: Array[Vector2i] = tower.get_adjacent_cells()

	for cell: Vector2i in adj_cells:
		var dir_vec: Vector2i = cell - tower.tower_position

		if self.has_method(&"_is_local_direction_allowed"): #for EffectDistributorBehavior
			if not self.call(&"_is_local_direction_allowed", tower.facing, dir_vec):
				continue

		var pos = Island.cell_to_position(cell)
		var rect: Rect2 = Rect2(pos - half_size, Vector2(cell_size, cell_size))

		canvas.preview_rect(rect, canvas.highlight_color, false, 1.0)

#a helper function for safe animation playback
func _play_animation(anim_name: StringName, custom_speed: float = 1.0) -> void:
	if is_instance_valid(animation_player) and animation_player.has_animation(anim_name):
		animation_player.play(anim_name, -1, custom_speed * Clock.speed_multiplier, custom_speed < 0.0)

#helper functions for child classes to use
func _is_attack_possible(target_needed: bool = true) -> bool:
	if attack_component == null or (target_needed and range_component == null):
		return false

	if unit.disabled:
		return false

	if unit.attack_only_when_blocked and not unit.blocked:
		return false

	#print(attack_component, " ", attack_component.attack_data)
	if attack_component.current_cooldown <= 0.0:
		if not target_needed:
			return true

		var target = range_component.get_target() as Unit
		if target:
			return true

	return false

func _attempt_simple_attack() -> bool: ##fires one ordinary targeted attack while querying range only once for this update
	if attack_component == null or range_component == null:
		return false

	if unit.disabled:
		return false

	if unit.attack_only_when_blocked and not unit.blocked:
		return false

	if attack_component.current_cooldown > 0.0:
		return false

	var target: Unit = range_component.get_target() as Unit
	if not target:
		return false

	attack_component.attack(target)
	unit.queue_redraw()
	return true

func _attempt_navigate_to_origin() -> bool:
	if not is_instance_valid(navigation_component):
		return false

	navigation_component.goal = Vector2i.ZERO
	return true

func _get_valid_spawn_position_near(origin_position: Vector2, radius: float, max_attempts: int = 10) -> Vector2:
	var island: Island = Run.references.island
	if not is_instance_valid(island):
		return origin_position

	for i: int in range(max_attempts):
		var offset: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.0, radius)
		var candidate: Vector2 = origin_position + offset
		var cell: Vector2i = Island.position_to_cell(candidate)
		if not Navigation.grid.has(cell):
			continue
		if _is_spawn_cell_blocked(island, cell):
			continue
		return candidate

	return origin_position

func _is_spawn_cell_blocked(island: Island, cell: Vector2i) -> bool:
	if not island.tower_grid.has(cell):
		return false

	var tower: Tower = island.tower_grid[cell]
	return is_instance_valid(tower) and tower.blocks_tile_at_cell(cell)

func get_save_data() -> Dictionary:
	return {}

func load_save_data(_save_data: Dictionary) -> void:
	attach()
