extends Unit
class_name Tower

signal adjacency_updated(new_adjacencies: Dictionary[Vector2i, Tower]) #Island fires this for us

@export var type: Towers.Type
@export var blocking: bool = true ##does this tower block enemy units from passing through?

@export var turret: Node2D ##this is the part of the turret that turns to face and shoot

enum Facing {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

enum State { ACTIVE, RUINED } ##overarching state machine of the tower
var current_state: State = State.ACTIVE #NOTE: should not be directly modified
var level: int = 0: #upgrade level of tower
	set(new_level):
		level = new_level
		UI.update_unit_state.emit(self)
var facing: Facing: #which direction the tower is facing
	set(new_facing):
		facing = new_facing
		if graphics:
			graphics.rotation = facing * PI * 0.5
var tower_position: Vector2i = Vector2i.ZERO:
	set(new_pos):
		#if new_pos == tower_position:
			#return

		tower_position = new_pos
		movement_component.unit = self #evil circular dependency resolution
		movement_component.position = Island.cell_to_position(tower_position) + Vector2(size) * 0.5 * Island.CELL_SIZE - Vector2(0.5, 0.5) * Island.CELL_SIZE
		
		# --- apply terrain modifiers ---
		# after the tower is created and has its components, check the terrain it's on
		# clear pre-existing terrain modifiers
		for terrain_modifier: Modifier in _terrain_modifiers:
			modifiers_component.remove_modifier(terrain_modifier)
		_terrain_modifiers.clear()
		
		var total_area: float = float(size.x * size.y)
		var modifier_counts: Dictionary[ModifierDataPrototype, int] = {}
		for x: int in size.x:
			for y: int in size.y:
				var check_cell: Vector2i = tower_position + Vector2i(x, y)
				
				# Get terrain at this specific tile
				var terrain_base: Terrain.Base = References.island.get_terrain_base(check_cell)
				var modifier_prototypes: Array[ModifierDataPrototype] = Terrain.get_modifiers_for_base(terrain_base)
				
				for proto: ModifierDataPrototype in modifier_prototypes:
					if not modifier_counts.has(proto):
						modifier_counts[proto] = 0
					modifier_counts[proto] += 1

		# generate and scale the final modifiers
		for proto: ModifierDataPrototype in modifier_counts:
			var tile_count: int = modifier_counts[proto]
			var proportion: float = float(tile_count) / total_area
			
			# If the tower is fully on this terrain (proportion == 1.0), it gets full effect.
			# If it's half on (0.5), it gets half effect.
			
			var new_modifier: Modifier = proto.generate_modifier()

			if new_modifier.additive != 0.0:
				new_modifier.additive *= proportion

			if new_modifier.multiplicative != 1.0:
				var deviation: float = new_modifier.multiplicative - 1.0
				new_modifier.multiplicative = 1.0 + (deviation * proportion)
			
			_terrain_modifiers.append(new_modifier)
			modifiers_component.add_modifier(new_modifier)

var _terrain_modifiers: Array[Modifier] = [] ## modifiers for terrain effects (i.e. high ground)
var size: Vector2i = Vector2i.ONE ## this is inclusive of facing

# --- new state transition functions ---

# this function is called by 'sell()' or 'on_killed()'
func enter_ruin_state(reason: RuinService.RuinReason) -> void:
	if current_state == State.RUINED:
		return

	if Phases.current_phase != Phases.GamePhase.COMBAT_WAVE:
		queue_free()
		return
		
	current_state = State.RUINED
	
	# 1. register with the service
	Player.ruin_service.register_ruin(self, reason)
	
	# 2. update visuals
	disabled = true
	
	# 3. become non-blocking for pathfinding
	self.blocking = false
	References.island.update_navigation_grid()

func enter_active_state() -> void:
	if current_state == State.ACTIVE:
		return
	current_state = State.ACTIVE
	#restore visuals
	disabled = false
	#become blocking again
	self.blocking = true
	References.island.update_navigation_grid()
	#reenable components
	if is_instance_valid(attack_component): attack_component.set_process(true)
	if is_instance_valid(range_component): range_component.set_process(true)

# this function is called by the RuinService at the end of a wave
func resurrect() -> void:
	# 1. restore state
	enter_active_state()
	# 2. restore health
	if is_instance_valid(health_component):
		health_component.health = health_component.get_stat(modifiers_component, health_component.health_data, Attributes.id.MAX_HEALTH)
	# 3. restart behaviours
	behavior.start()
	# 4. reattach all effects
	for effect_prototype: EffectPrototype in effect_prototypes:
		apply_effect(effect_prototype) #attach all effects

func on_killed(_hit_report_data: HitReportData) -> void:
	enter_ruin_state(RuinService.RuinReason.KILLED)
	for effect_prototype: EffectPrototype in effect_prototypes:
		remove_effect(effect_prototype) #detach all effects

func sell():
	if not abstractive and current_state == State.ACTIVE:
		Player.flux += flux_value #full refund!
		enter_ruin_state(RuinService.RuinReason.SOLD)
		died.emit(HitReportData.blank_hit_report)

func _create_hitbox():
	hitbox = Hitbox.new()
	var collision_shape := CollisionShape2D.new()
	var shape_bound := RectangleShape2D.new()
	shape_bound.size = size * Island.CELL_SIZE
	
	collision_shape.shape = shape_bound
	hitbox.collision_mask = 0
	hitbox.collision_layer = Hitbox.get_mask(hostile)
	hitbox.unit = self

	
	hitbox.add_child(collision_shape)
	add_child.call_deferred(hitbox)
		
func _ready():
	name = name + " " + str(unit_id)
	level = 1
	
	_setup_event_bus()
	_attach_intrinsic_effects()
	_create_components()
	_prepare_components()
	_create_hitbox()
	
	if not is_instance_valid(behavior):
		behavior = DefaultBehavior.new()
		add_child(behavior)
	
	is_ready = true
	components_ready.emit()
	behavior.initialise(self)

	adjacency_updated.connect(func(new_adjacencies: Dictionary[Vector2i, Tower]): #receive data from Island
		var adjacency_data := AdjacencyReportData.new() #broadcast into effects system
		adjacency_data.adjacent_towers = new_adjacencies
		adjacency_data.pivot = self
		
		var event := GameEvent.new()
		event.event_type = GameEvent.EventType.ADJACENCY_UPDATED
		event.data = adjacency_data
		
		on_event.emit(event)
	)
	
	Phases.wave_ended.connect(func(_wave_number: int): #heal up at the end of every wave
		if is_instance_valid(health_component):
			health_component.health = health_component.max_health
	)
	
	var build_data := BuildTowerData.new()
	build_data.tower = self
	var evt := GameEvent.new()
	evt.event_type = GameEvent.EventType.TOWER_BUILT
	evt.data = build_data
	
	if not abstractive:
		Player.on_event.emit(null, evt) #fire global event (that we just got built)
	
func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in size.x:
		for y: int in size.y:
			cells.append(tower_position + Vector2i(x,y))
			
	return cells

func get_adjacent_cells() -> Array[Vector2i]: ##returns an array of all valid grid coordinates immediately adjacent to this tower
	var neighbors: Array[Vector2i] = []
	var start: Vector2i = tower_position
	var width: int = size.x
	var height: int = size.y

	for x: int in width: #top and bottom edges
		# cell immediately above
		neighbors.append(Vector2i(start.x + x, start.y - 1))
		# cell immediately below
		neighbors.append(Vector2i(start.x + x, start.y + height))

	for y: int in height: #left and right edges
		#cell immediately to the left
		neighbors.append(Vector2i(start.x - 1, start.y + y))
		#cell immediately to the right
		neighbors.append(Vector2i(start.x + width, start.y + y))

	return neighbors
	
func get_adjacent_towers() -> Dictionary[Vector2i, Tower]:
	if behavior.has_method(&"get_adjacent_towers"):
		return behavior.get_adjacent_towers()
	
	var adjacencies: Dictionary[Vector2i, Tower]
	for cell: Vector2i in get_adjacent_cells():
		var tower : Tower = References.island.get_tower_on_tile(cell)
		if tower:
			adjacencies[cell] = tower
			
	return adjacencies
	
static func get_side_from_offset(tower_size: Vector2i, rel_offset: Vector2i) -> Facing:
	# 1. Check Vertical Sides (Top/Bottom)
	# The offset must be within the tower's horizontal bounds (x: 0 to width-1)
	if rel_offset.x >= 0 and rel_offset.x < tower_size.x:
		if rel_offset.y < 0: 
			return Facing.UP
		if rel_offset.y >= tower_size.y: 
			return Facing.DOWN

	# 2. Check Horizontal Sides (Left/Right)
	# The offset must be within the tower's vertical bounds (y: 0 to height-1)
	if rel_offset.y >= 0 and rel_offset.y < tower_size.y:
		if rel_offset.x < 0: 
			return Facing.LEFT
		if rel_offset.x >= tower_size.x: 
			return Facing.RIGHT

	# 3. Fallback (Diagonal corner or Inside tower)
	return 10

func get_navcost_for_cell(_cell: Vector2i) -> int: ##returns navigation cost for a specific tile occupied by this tower
	if behavior.has_method(&"get_navcost_for_cell"): #allows behaviors to override default behaviour
		return behavior.get_navcost_for_cell(_cell)
	return Towers.get_tower_navcost(self.type)
