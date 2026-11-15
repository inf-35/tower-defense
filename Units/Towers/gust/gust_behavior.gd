extends Behavior

class TrackedEnemy extends RefCounted:
	var enemy: Unit
	var speed_modifier: Modifier

@export_range(0.0, 1.0, 0.01) var speed_change: float = 0.65 ##fraction of speed gained away from the tower or lost towards it
@export_range(0.01, 1.0, 0.01) var refresh_interval: float = 0.10 ##game time between center-tile and heading checks
@export var gust_area: Area2D ##shared enemy detector for the four lanes
@export var wind_vfx: VFXInfo ##swirl settings shared by the four outward streams
@export var fan_blades: Sprite2D ##sprite that spins around the fan hub
@export_range(0.0, 5.0, 0.05, "or_greater") var startup_seconds: float = 1.2 ##game time for the fan and streams to reach full speed
@export var fan_spin_degrees_per_second: float = 1080.0 ##angular speed once the fan reaches full power

var _tracked_enemies: Dictionary[int, TrackedEnemy] = {}
var _elapsed: float = 0.0
var _active: bool = false
var _range_tiles: int = -1
var _lane_shape: RectangleShape2D
var _lanes: Array[CollisionShape2D] = []
var _wind_streams: Dictionary[Vector2i, SwirlLineVFX] = {}
var _startup_progress: float = 0.0

func start() -> void: ##builds the cross once and connects its combined overlap events
	set_physics_process(false)
	wind_vfx.swirl_color = Color(0.52, 0.80, 1.0, 0.55)
	gust_area.collision_mask = Hitbox.get_mask(true)
	_lane_shape = RectangleShape2D.new()
	for direction: Vector2i in Island.DIRS:
		var lane := CollisionShape2D.new()
		lane.shape = _lane_shape
		lane.rotation = Vector2(direction).angle()
		gust_area.add_child(lane)
		_lanes.append(lane)
	gust_area.area_entered.connect(_on_enemy_entered)
	gust_area.area_exited.connect(_on_enemy_exited)
	modifiers_component.stat_changed.connect(_on_stat_changed)
	attach()

func attach() -> void: ##starts the fan and restores detection after placement or reactivation
	if _active:
		return
	_active = true
	_startup_progress = 0.0 if startup_seconds > 0.0 else 1.0
	set_process(true)
	_refresh_range.call_deferred()

func detach() -> void: ##releases this tower's speed modifiers, status ownership, and visual streams
	_active = false
	set_process(false)
	set_physics_process(false)
	_elapsed = 0.0
	_range_tiles = -1
	if is_instance_valid(gust_area):
		gust_area.set_deferred(&"monitoring", false)
	for tracked: TrackedEnemy in _tracked_enemies.values():
		_release_gust(tracked)
	_tracked_enemies.clear()
	_clear_wind_streams()

func _on_stat_changed(attribute: Attributes.id) -> void: ##defers shape changes beyond any physics overlap callback
	if _active and attribute == Attributes.id.RANGE:
		_refresh_range.call_deferred()

func _get_range_tiles() -> int: ##converts the effective attack range to whole cardinal cells, as snowball does
	return maxi(0, floori(attack_component.range / Island.CELL_SIZE))

func _refresh_range() -> void: ##resizes detection and streams together when effective range crosses a cell boundary
	if not _active or unit.disabled or unit.is_queued_for_deletion():
		return
	var next_range: int = _get_range_tiles()
	gust_area.monitoring = next_range > 0
	if _range_tiles == next_range:
		return
	_range_tiles = next_range
	if _range_tiles == 0:
		for tracked: TrackedEnemy in _tracked_enemies.values():
			_release_gust(tracked)
		_tracked_enemies.clear()
		set_physics_process(false)
		_clear_wind_streams()
		return

	var lane_length: float = _range_tiles * Island.CELL_SIZE
	var lane_offset: float = (lane_length + Island.CELL_SIZE) * 0.5
	var origin: Vector2 = unit.global_position
	_lane_shape.size = Vector2(lane_length, Island.CELL_SIZE)
	for lane_index: int in _lanes.size():
		var direction: Vector2i = Island.DIRS[lane_index]
		_lanes[lane_index].position = Vector2(direction) * lane_offset
		var end: Vector2 = origin + Vector2(direction) * lane_length
		var stream: SwirlLineVFX = _wind_streams.get(direction)
		if is_instance_valid(stream):
			stream.set_segment(origin, end)
			continue
		stream = VFXManager.create_swirl_beam_info(wind_vfx, origin, end, 1.0, true)
		if is_instance_valid(stream):
			stream.flow_strength = _startup_progress
			_wind_streams[direction] = stream

func _clear_wind_streams() -> void: ##stops streams on suspension, removal, or zero range
	for stream: SwirlLineVFX in _wind_streams.values():
		if is_instance_valid(stream):
			stream.stop()
	_wind_streams.clear()

func _exit_tree() -> void:
	detach()

func update(_delta: float) -> void: ##gust has no attack or cooldown
	pass

func _process(_delta: float) -> void: ##ramps the fan and wind together, then holds the fan at its running speed
	var delta: float = Clock.game_delta
	if _startup_progress < 1.0:
		_startup_progress = move_toward(_startup_progress, 1.0, delta / maxf(startup_seconds, 0.001))
		for stream: SwirlLineVFX in _wind_streams.values():
			if is_instance_valid(stream):
				stream.flow_strength = _startup_progress
	if is_instance_valid(fan_blades):
		fan_blades.rotate(deg_to_rad(fan_spin_degrees_per_second) * _startup_progress * delta)

func _physics_process(_delta: float) -> void: ##checks heading only while the area has nearby enemies
	_elapsed += Clock.physics_game_delta
	if _elapsed < refresh_interval:
		return
	_elapsed = 0.0
	for enemy_id: int in _tracked_enemies.keys():
		var tracked: TrackedEnemy = _tracked_enemies[enemy_id]
		if not is_instance_valid(tracked.enemy) or tracked.enemy.is_queued_for_deletion():
			_release_gust(tracked)
			_tracked_enemies.erase(enemy_id)
			continue
		_refresh_gust(tracked)
	set_physics_process(not _tracked_enemies.is_empty())

func _on_enemy_entered(area: Area2D) -> void: ##tracks hitbox candidates and immediately checks their center tile
	if not _active or unit.disabled:
		return
	var hitbox := area as Hitbox
	if not is_instance_valid(hitbox):
		return
	var enemy: Unit = hitbox.unit
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.hitbox != hitbox or enemy is Tower or not enemy.hostile:
		return
	if not is_instance_valid(enemy.movement_component) or not is_instance_valid(enemy.modifiers_component):
		return
	var enemy_id: int = enemy.get_instance_id()
	if _tracked_enemies.has(enemy_id):
		return
	var tracked := TrackedEnemy.new()
	tracked.enemy = enemy
	_tracked_enemies[enemy_id] = tracked
	_refresh_gust(tracked)
	set_physics_process(true)

func _on_enemy_exited(area: Area2D) -> void: ##drops candidates as soon as their hitbox leaves all four lanes
	var hitbox := area as Hitbox
	if not is_instance_valid(hitbox) or not is_instance_valid(hitbox.unit) or hitbox.unit.hitbox != hitbox:
		return
	var enemy_id: int = hitbox.unit.get_instance_id()
	var tracked: TrackedEnemy = _tracked_enemies.get(enemy_id)
	if tracked == null:
		return
	_tracked_enemies.erase(enemy_id)
	_release_gust(tracked)
	set_physics_process(not _tracked_enemies.is_empty())

func _refresh_gust(tracked: TrackedEnemy) -> void: ##applies wind only when the enemy center is in one of the four lanes
	var enemy: Unit = tracked.enemy
	var tower: Tower = unit as Tower
	var offset: Vector2i = Island.position_to_cell(enemy.global_position) - tower.tower_position
	var distance: int = absi(offset.x) + absi(offset.y)
	if distance == 0 or distance > _range_tiles or (offset.x != 0 and offset.y != 0):
		_release_gust(tracked)
		return

	var outward: Vector2 = tower.global_position.direction_to(enemy.global_position)
	var alignment: float = clampf(enemy.movement_component.target_direction.dot(outward), -1.0, 1.0)
	var multiplier: float = 1.0 + speed_change * alignment
	if tracked.speed_modifier != null:
		if not is_equal_approx(tracked.speed_modifier.multiplicative, multiplier):
			tracked.speed_modifier.multiplicative = multiplier
			enemy.modifiers_component.change_modifier(tracked.speed_modifier)
		return

	#leave the effect with its current source until that field releases it.
	if enemy.modifiers_component.has_status(Attributes.Status.GUSTED):
		return
	tracked.speed_modifier = Modifier.new(Attributes.id.MAX_SPEED, multiplier, 0.0, -1.0, null, tower.unit_id)
	enemy.modifiers_component.add_status(Attributes.Status.GUSTED, 1.0, -1.0, tower.unit_id)
	enemy.modifiers_component.add_modifier(tracked.speed_modifier)

func _release_gust(tracked: TrackedEnemy) -> void: ##clears the effect only if this tower applied it
	var enemy: Unit = tracked.enemy
	if tracked.speed_modifier == null or not is_instance_valid(enemy) or not is_instance_valid(enemy.modifiers_component):
		return
	enemy.modifiers_component.remove_modifier(tracked.speed_modifier)
	tracked.speed_modifier = null
	enemy.modifiers_component.remove_status(Attributes.Status.GUSTED)

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##highlights the same cardinal footprint used by the detector
	var tower: Tower = unit as Tower
	if not is_instance_valid(tower) or (tower.disabled and not tower.abstractive):
		return []
	var range_tiles: int = _get_range_tiles()
	if range_tiles == 0:
		return []
	var cells: Array[Vector2i] = []
	for direction: Vector2i in Island.DIRS:
		for distance: int in range(1, range_tiles + 1):
			cells.append(tower.tower_position + direction * distance)
	return [TowerInfluence.for_cells(&"gust", TowerInfluence.Kind.ATTACK, cells, null, [], false, TowerInfluence.Scope.WORLD)]
