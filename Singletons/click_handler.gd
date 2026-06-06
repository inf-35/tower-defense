extends Node

#--- state management ---
enum State { IDLE, PREVIEWING, ENTITY_SELECTED }
var current_state: State = State.IDLE

#--- properties ---
var enabled: bool = false
var selected_entity: Unit ##the unit instance currently selected on the map
var preview_tower_prototype: Tower   #the tower type being previewed for building
var preview_tower_position: Vector2i
var preview_tower_facing: Tower.Facing
var preview_is_valid: bool
#--- new state variable for managing "ghost" units for inspection
var _ghost_unit_for_inspection: Unit = null

var current_preview: TowerPreview

signal tower_was_selected(tower: Tower)
signal tower_was_deselected()

func _ready() -> void:
	if not Run.is_run_ready():
		await Run.references_ready

	UI.tower_selected.connect(_on_build_tower_selected)
	UI.update_flux.connect(func(_flux: float): _update_preview_visuals())
	UI.update_capacity.connect(func(_used: float, _total: float): _update_preview_visuals())

func start() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	current_state = State.IDLE
	preview_tower_prototype = null
	selected_entity = null
	_ghost_unit_for_inspection = null

	current_preview = Run.references.tower_preview
	enabled = true

func _process(_delta: float) -> void:
	if not Run.is_run_ready():
		return

	if not Run.phases.in_game:
		return
	if not enabled or not is_instance_valid(UI.cursor_info):
		return
	if not is_instance_valid(Run.references.camera):
		return

	match current_state:
		State.IDLE:
			_update_idle_tooltip()
		State.PREVIEWING:
			_update_preview_tooltip()
		State.ENTITY_SELECTED:
			#hide tooltip if a tower is selected (cleaner ui)
			UI.cursor_info.display_message("")

func _update_idle_tooltip() -> void:
	if get_viewport() == null:
		return

	var mouse_pos = Run.references.camera.get_global_mouse_position()
	var cell = Island.position_to_cell(mouse_pos)
	var island = Run.references.island
	var msg: String = ""

	#priority 1: hovering over a unit/enemy?
	#(requires raycast or iterating active enemies. optional implementation)

	#priority 2: hovering over a tower?
	var tower = island.get_tower_on_tile(cell)
	if tower:
		msg = Towers.get_tower_name(tower.type)
		#optional: add status info
		if tower.modifiers_component.has_status(Attributes.Status.FROST):
			msg += " (Frozen)"

	#priority 3: terrain info
	else:
		msg = _get_cell_tooltip(island, cell)

	UI.cursor_info.display_message(msg, false)

func _update_preview_tooltip() -> void:
	#if placement is valid, show cost or nothing
	var cell := Island.position_to_cell(Run.references.camera.get_global_mouse_position())
	var island := Run.references.island

	if preview_is_valid:
		var msg: String = ""
		#if it's a rite, show inventory count
		if Towers.is_tower_rite(preview_tower_prototype.type):
			var count = Run.player.get_rite_count(preview_tower_prototype.type)
			msg += "Rite Available: %d\n" % count

		msg += _get_cell_tooltip(island, cell)
		msg += "\nLMB to place\nRMB to deselect\nR to rotate"
		UI.cursor_info.display_message(msg, false)
	else:
		#if invalid, get the specific reason
		#note: we used 'preview_tower_position' which was calculated in _update_preview_visuals
		var error_msg: String = ""
		if _is_uncharted_lake_cell(island, cell):
			error_msg = _get_cell_tooltip(island, cell)
		else:
			error_msg = TerrainService.get_construction_error_message(
				Run.references.island,
				preview_tower_position,
				preview_tower_prototype
			)
		error_msg += "\nLMB to place\nRMB to deselect\nR to rotate"
		UI.cursor_info.display_message(error_msg, true)

func _get_clicked_enemy(mouse_pos: Vector2) -> Unit: ##helper to find enemy under mouse
	if not is_instance_valid(Run.references.island): return null
	var space_state = Run.references.island.get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = mouse_pos
	#target ememy layer
	query.collision_mask = Hitbox.get_mask(true)
	query.collide_with_areas = true

	var results = space_state.intersect_point(query)
	if not results.is_empty():
		var hitbox = results[0].collider as Hitbox
		if is_instance_valid(hitbox) and is_instance_valid(hitbox.unit):
			return hitbox.unit
	return null

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	match current_state:
		State.IDLE:
			_handle_idle_input(event)
		State.PREVIEWING:
			_handle_preview_input(event)
		State.ENTITY_SELECTED:
			_handle_tower_selected_input(event)

	#rotation can be handled universally if a preview is active
	if current_state == State.PREVIEWING and event.is_action_pressed("rotate_preview"):
		preview_tower_facing = (preview_tower_facing + 1) % Tower.Facing.size() as Tower.Facing
		var base_size: Vector2 = Towers.get_tower_size(preview_tower_prototype.type)
		preview_tower_prototype.size = Tower.get_rotated_size(base_size, preview_tower_facing)
		preview_tower_position = _recalculate_preview_position()
		_update_preview_visuals()

func _enter_idle_state() -> void:
	#deselect any tower and hide any preview.
	if is_instance_valid(selected_entity):
		selected_entity = null
		tower_was_deselected.emit()

	#critical: ensure the ghost unit is destroyed when leaving a selection state
	if is_instance_valid(_ghost_unit_for_inspection):
		_ghost_unit_for_inspection.free()
		_ghost_unit_for_inspection = null

	if is_instance_valid(preview_tower_prototype):
		Towers.reset_tower_prototype(preview_tower_prototype.type)

	if is_instance_valid(Run.references.path_renderer):
		Run.references.path_renderer.clear_preview()

	if is_instance_valid(current_preview):
		current_preview.hide()

	current_state = State.IDLE

func _enter_preview_state(tower: Tower) -> void:
	if current_state == State.ENTITY_SELECTED or current_state == State.PREVIEWING:
		_enter_idle_state() #reset to a clean state first

	current_state = State.PREVIEWING
	preview_tower_prototype = tower
	preview_tower_prototype.visible = false
	preview_tower_prototype.modulate = Color(1,1,1,0.6)
	current_preview.setup(preview_tower_prototype.type)
	current_preview.show()
	#trigger an immediate update of the preview at the current mouse position
	_update_preview_visuals()
	#lock on range indicator
	Run.references.range_indicator.select(preview_tower_prototype)

func _enter_tower_selected_state(tower: Tower) -> void:
	if current_state == State.PREVIEWING or current_state == State.ENTITY_SELECTED:
		_enter_idle_state() #reset to a clean state first

	current_state = State.ENTITY_SELECTED
	selected_entity = tower
	tower_was_selected.emit(selected_entity)
	UI.update_inspector_bar.emit(selected_entity)

	Audio.play_sound(ID.Sounds.BUTTON_CLICK_SOUND, -5.0)
	Run.references.range_indicator.select(tower)

func _enter_entity_selected_state(entity: Unit) -> void:
	if current_state == State.PREVIEWING or current_state == State.ENTITY_SELECTED:
		_enter_idle_state()

	current_state = State.ENTITY_SELECTED
	selected_entity = entity

	if entity is Tower:
		tower_was_selected.emit(entity)
		Run.references.range_indicator.select(entity)
	else:
		pass
		#Run.references.range_indicator.deselect() # Or implement an enemy range indicator

	UI.update_inspector_bar.emit(selected_entity)
	Audio.play_sound(ID.Sounds.BUTTON_CLICK_SOUND, -5.0)

#input handlers
func _handle_idle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		#only thing we can do in the idle state is select a tower
		var mouse_pos: Vector2 = Run.references.camera.get_global_mouse_position()
		var cell_pos: Vector2i = Island.position_to_cell(mouse_pos)

		#check for a previewed feature from the expansionservice
		var preview_data: Terrain.CellData = Run.references.island.expansion_service.get_preview_data_at_cell(cell_pos)
		if is_instance_valid(preview_data) and preview_data.feature != Towers.Type.VOID:
			#preview found! create a temporary "ghost" unit for inspection.
			_create_and_inspect_ghost_unit(preview_data, cell_pos)
			return #stop further processing
		#check for towers
		if Run.references.island.tower_grid.has(cell_pos):
			var clicked_tower: Tower = Run.references.island.tower_grid[cell_pos]
			_enter_tower_selected_state(clicked_tower)
			return
		#check for enemies last
		var clicked_enemy = _get_clicked_enemy(mouse_pos)
		if clicked_enemy:
			_enter_entity_selected_state(clicked_enemy)
			return
		#else do nothing

func _handle_preview_input(event: InputEvent) -> void:
	Run.references.range_indicator.select(preview_tower_prototype)
	#handle mouse motion to update the preview visuals
	if event is InputEventMouseMotion:
		preview_tower_position = _recalculate_preview_position()
		if preview_tower_position != preview_tower_prototype.tower_position or preview_tower_facing != preview_tower_prototype.facing:
			_update_preview_visuals()

	#handle clicks to place or cancel
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_LEFT:
			#if the placement is valid, emit the request.
			if preview_is_valid:
				#use the last known valid position for the request.
				UI.place_tower_requested.emit(preview_tower_prototype.type, preview_tower_position, preview_tower_facing)
				#we don't transition back to idle. this allows the player to build multiple towers at once
				#this switches the inspector to the newly built tower (line below)
				if Run.references.island.tower_grid.has(preview_tower_position):
					UI.update_inspector_bar.emit(Run.references.island.tower_grid[preview_tower_position])

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			#right-click cancels the preview.
			_enter_idle_state()

func _handle_tower_selected_input(event: InputEvent) -> void:
	#any click while a tower is selected will deselect it.
	if Run.references.camera and event is InputEventMouseButton and event.is_pressed():
		var mouse_pos: Vector2 = Run.references.camera.get_global_mouse_position()
		var cell_pos: Vector2i = Island.position_to_cell(mouse_pos)

		#check for previews first
		var preview_data: Terrain.CellData = Run.references.island.expansion_service.get_preview_data_at_cell(cell_pos)
		if is_instance_valid(preview_data) and preview_data.feature != Towers.Type.VOID:
			_create_and_inspect_ghost_unit(preview_data, cell_pos)
			return

		if Run.references.island.tower_grid.has(cell_pos): #seamlessly switches between towers
			var clicked_tower = Run.references.island.tower_grid[cell_pos]
			_enter_tower_selected_state(clicked_tower)
		else: #otherwise transition to idle
			_enter_idle_state()
		#check for enemies last
		var clicked_enemy = _get_clicked_enemy(mouse_pos)
		if clicked_enemy:
			_enter_entity_selected_state(clicked_enemy)
			return
		#else do nothing


#--- helper functions ---
func _recalculate_preview_position() -> Vector2i:
	var mouse_pos: Vector2 = Run.references.camera.get_global_mouse_position()
	var base_size: Vector2i = Towers.get_tower_size(preview_tower_prototype.type)
	var effective_size: Vector2i = Tower.get_rotated_size(base_size, preview_tower_facing)
	var center_offset: Vector2i = effective_size * 0.5
	return Island.position_to_cell(mouse_pos) - center_offset

func _get_cell_tooltip(island: Island, cell: Vector2i) -> String:
	if island.terrain_base_grid.has(cell):
		var terrain: Terrain.Base = island.get_terrain_base(cell)
		var msg: String = Terrain.Base.keys()[terrain].capitalize()
		if terrain == Terrain.Base.HIGHLAND:
			msg += "\n(Range Bonus)"
		elif terrain == Terrain.Base.SETTLEMENT:
			msg += "\n(Used to build villages)"
		elif terrain == Terrain.Base.WATER:
			msg += "\n(Blocks building and movement)"
		return msg

	if _is_uncharted_lake_cell(island, cell):
		return "Uncharted Water\n(Blocks building and movement once revealed)"

	return "Uncharted"

func _is_uncharted_lake_cell(island: Island, cell: Vector2i) -> bool:
	return island.is_lake_cell(cell) and not island.terrain_base_grid.has(cell)

func _update_preview_visuals() -> void:
	if not preview_tower_prototype:
		return

	if current_state != State.PREVIEWING:
		return

	Audio.play_sound(ID.Sounds.BUTTON_HOVER_SOUND, -10.0, preview_tower_position)
	preview_tower_prototype.tower_position = preview_tower_position
	preview_tower_prototype.facing = preview_tower_facing
	preview_tower_prototype.size = Tower.get_rotated_size(Towers.get_tower_size(preview_tower_prototype.type), preview_tower_prototype.facing)

	var occupied_cells: Array[Vector2i] = []
	var size := preview_tower_prototype.size

	for x in size.x:
		for y in size.y:
			var navcost: float = preview_tower_prototype.get_navcost_for_cell(preview_tower_position + Vector2i(x,y))
			if not is_equal_approx(navcost, Navigation.BASE_COST): #filter out cells marked as transparent
				occupied_cells.append(preview_tower_position + Vector2i(x, y))

	#send to path renderer
	if is_instance_valid(Run.references.path_renderer):
		Run.references.path_renderer.update_preview(occupied_cells)

	preview_is_valid = TerrainService.is_area_constructable(Run.references.island, preview_tower_facing, preview_tower_position, preview_tower_prototype.type, true)
	current_preview.update_visuals(preview_is_valid, preview_tower_facing, preview_tower_position)


#new helper to create and manage the temporary inspection unit
func _create_and_inspect_ghost_unit(cell_data: Terrain.CellData, cell_pos: Vector2i) -> void: ##for terrain preview!
	#first, clean up any previous state
	_enter_idle_state()

	#create the temporary tower instance
	_ghost_unit_for_inspection = Towers.create_tower(cell_data.feature)
	if not is_instance_valid(_ghost_unit_for_inspection):
		return #failed to create

	#configure the ghost unit
	_ghost_unit_for_inspection.abstractive = true #important: prevents it from interacting with gameplay
	_ghost_unit_for_inspection.visible = false
	_ghost_unit_for_inspection.tower_position = cell_pos

	#pass the preview's initial state data to the ghost unit so its behavior is configured correctly
	if not cell_data.initial_state.is_empty():
		_ghost_unit_for_inspection.set_initial_behaviour_state(cell_data.initial_state)

	#add it to the scene tree so it's a valid node
	add_child(_ghost_unit_for_inspection)

	#transition to the tower_selected state using the ghost unit
	#we don't call the full _enter_tower_selected_state because we don't want to
	#clear the ghost; we just set the state and tell the inspector to update.
	current_state = State.ENTITY_SELECTED
	selected_entity = _ghost_unit_for_inspection
	tower_was_selected.emit(selected_entity)
	UI.update_inspector_bar.emit(selected_entity)

#--- signal connections ---
func _on_build_tower_selected(tower: Tower) -> void:
	if not tower.is_ready:
		await tower.components_ready
	#the ui is requesting to start building a tower.
	_enter_preview_state(tower)
