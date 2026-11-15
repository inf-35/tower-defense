extends Behavior

const LAVA_GROUND_SCENE: PackedScene = preload("res://Units/Towers/caldera/lava_ground.tscn")
const LAVA_SLOW_META: StringName = &"caldera_lava_slow"
const LAVA_SPEED_MULTIPLIER: float = 0.5
const GLOW_FADE_IN_FRACTION: float = 0.14
const GLOW_START_SCALE: float = 0.40
const GLOW_END_SCALE: float = 1.5
const GLOW_ROTATION_STEP_DEGREES: float = 137.5

class LavaTile extends RefCounted:
	var ground: CalderaLavaGround
	var collision: CollisionShape2D

class LavaSlow extends RefCounted:
	var modifier: Modifier
	var owners: int = 0

@export var lava_area: Area2D ##detector shared by all of this tower's covered tiles
@export_range(0.0, 2.0, 0.01, "or_greater") var lava_transition_seconds: float = 0.35 ##time for tile coverage to grow or recede after the board changes
@export var glow: Sprite2D ##authored sprite and pivot for the overlapping fountain pulses
@export_range(0.1, 8.0, 0.05, "or_greater") var glow_lifetime: float = 2.4 ##game seconds for each expanding glow to fade out
@export var glow_spin_degrees_per_second: float = 10.0 ##shared spin speed for every pulse, with negative values reversing direction

var _island: Island
var _refresh_queued: bool = false
var _tile_shape: RectangleShape2D
var _lava_tiles: Dictionary[Vector2i, LavaTile] = {}
var _targets: Dictionary[int, WeakRef] = {}
var _brush_mask: Texture2D
var _brush_bounds: Rect2
var _glow_sprites: Array[Sprite2D] = []
var _glow_elapsed: float = 0.0
var _glow_scale: Vector2
var _glow_rotation: float
var _glow_alpha: float

func start() -> void: ##sets up the local lava detector and the two reusable glow sprites
	lava_area.collision_mask = Hitbox.get_mask(true)
	lava_area.area_entered.connect(_on_enemy_entered)
	lava_area.area_exited.connect(_on_enemy_exited)
	_tile_shape = RectangleShape2D.new()
	_tile_shape.size = Vector2.ONE * Island.CELL_SIZE
	if is_instance_valid(glow):
		_glow_scale = glow.scale
		_glow_rotation = glow.rotation
		_glow_alpha = glow.self_modulate.a
		glow.self_modulate.a = 0.0
		var second_glow := glow.duplicate() as Sprite2D
		var glow_parent: Node = glow.get_parent()
		glow_parent.add_child(second_glow)
		glow_parent.move_child(second_glow, glow.get_index() + 1)
		_glow_sprites = [glow, second_glow]
	attach()

func attach() -> void: ##rebuilds coverage from the settled board after placement, loading, or resurrection
	if is_instance_valid(_island) or not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return
	_island = Run.references.island
	_island.island_changed.connect(_queue_coverage_refresh)
	if not Run.is_run_ready():
		Run.references_ready.connect(_queue_coverage_refresh, CONNECT_ONE_SHOT)
	lava_area.set_deferred(&"monitoring", true)
	_queue_coverage_refresh()
	_glow_elapsed = 0.0
	set_process(not _glow_sprites.is_empty())

func detach() -> void: ##revokes this tower's slow ownership and stops its lava visuals
	set_process(false)
	for sprite: Sprite2D in _glow_sprites:
		if is_instance_valid(sprite):
			sprite.self_modulate.a = 0.0
	if is_instance_valid(_island) and _island.island_changed.is_connected(_queue_coverage_refresh):
		_island.island_changed.disconnect(_queue_coverage_refresh)
	if Run.references_ready.is_connected(_queue_coverage_refresh):
		Run.references_ready.disconnect(_queue_coverage_refresh)
	if is_instance_valid(lava_area):
		lava_area.set_deferred(&"monitoring", false)
	_refresh_queued = false
	for target_id: int in _targets.keys():
		_remove_target(target_id)
	for tile: LavaTile in _lava_tiles.values():
		_retire_tile(tile)
	_lava_tiles.clear()
	_brush_mask = null
	_island = null

func _exit_tree() -> void:
	detach()

func _process(_delta: float) -> void: ##recycles the glow sprites at half-lifetime intervals with a fresh starting angle each time
	_glow_elapsed += Clock.game_delta
	var lifetime: float = maxf(glow_lifetime, 0.1)
	for index: int in _glow_sprites.size():
		var elapsed: float = _glow_elapsed - index * lifetime * 0.5
		if elapsed < 0.0:
			continue
		var sprite: Sprite2D = _glow_sprites[index]
		var age: float = fposmod(elapsed, lifetime)
		var progress: float = age / lifetime
		var pulse_index: int = floori(elapsed / lifetime) * 2 + index
		var starting_angle: float = fposmod(pulse_index * GLOW_ROTATION_STEP_DEGREES, 360.0)
		var fade_in: float = smoothstep(0.0, GLOW_FADE_IN_FRACTION, progress)
		var fade_out: float = 1.0 - smoothstep(GLOW_FADE_IN_FRACTION, 1.0, progress)
		sprite.self_modulate.a = _glow_alpha * fade_in * fade_out
		sprite.scale = _glow_scale * lerpf(GLOW_START_SCALE, GLOW_END_SCALE, progress)
		sprite.rotation = _glow_rotation + deg_to_rad(starting_angle + glow_spin_degrees_per_second * age)

func _queue_coverage_refresh() -> void: ##coalesces layout changes before touching detector shapes or ground scenes
	if not is_instance_valid(_island) or _refresh_queued:
		return
	_refresh_queued = true
	_refresh_coverage.call_deferred()

func _refresh_coverage() -> void: ##uses the same adjacent cells for the detector and the shader tiles
	_refresh_queued = false
	if not Run.is_run_ready() or not is_instance_valid(_island) or _island != Run.references.island or _island.game_ending:
		return
	if not is_instance_valid(unit) or unit.disabled or unit.is_queued_for_deletion():
		return
	var terrain_rect: ColorRect = _island.terrain_renderer.terrain_rect
	var terrain_material := terrain_rect.material as ShaderMaterial
	var brush_mask := terrain_material.get_shader_parameter(&"brush_mask_texture") as Texture2D
	var brush_bounds := Rect2(terrain_rect.position, terrain_rect.size)
	var brush_mapping_changed: bool = brush_mask != _brush_mask or brush_bounds != _brush_bounds
	_brush_mask = brush_mask
	_brush_bounds = brush_bounds
	var cells: Array[Vector2i] = _get_covered_cells(unit as Tower, _island)
	for cell: Vector2i in _lava_tiles.keys():
		if cells.has(cell):
			continue
		_retire_tile(_lava_tiles[cell])
		_lava_tiles.erase(cell)
	for cell: Vector2i in cells:
		if _lava_tiles.has(cell):
			if brush_mapping_changed:
				_lava_tiles[cell].ground.bind_brush_patch(brush_mask, brush_bounds, cell)
			continue
		var tile := LavaTile.new()
		var center: Vector2 = Island.cell_to_position(cell)
		tile.ground = LAVA_GROUND_SCENE.instantiate() as CalderaLavaGround
		tile.ground.size = _tile_shape.size
		tile.ground.position = _island.to_local(center) - _tile_shape.size * 0.5
		tile.ground.bind_brush_patch(brush_mask, brush_bounds, cell)
		tile.ground.lavaness = 0.0
		_island.add_child(tile.ground)
		tile.ground.fade_to(1.0, lava_transition_seconds)
		tile.collision = CollisionShape2D.new()
		tile.collision.shape = _tile_shape
		tile.collision.position = lava_area.to_local(center)
		lava_area.add_child(tile.collision)
		_lava_tiles[cell] = tile

func _retire_tile(tile: LavaTile) -> void: ##lets the ground recede after its gameplay coverage ends
	if is_instance_valid(tile.collision):
		tile.collision.set_deferred(&"disabled", true)
		tile.collision.queue_free()
	if not is_instance_valid(tile.ground):
		return
	if is_instance_valid(_island) and tile.ground.is_inside_tree() and not _island.game_ending:
		tile.ground.fade_to(0.0, lava_transition_seconds, true)
	else:
		tile.ground.queue_free()

func _get_covered_cells(tower: Tower, island: Island) -> Array[Vector2i]: ##shares revealed land coverage between live lava and previews
	var cells: Array[Vector2i] = []
	for cell: Vector2i in tower.get_adjacent_cells():
		if island.terrain_base_grid.has(cell) and not Terrain.is_waterlike(island.terrain_base_grid[cell]):
			cells.append(cell)
	return cells

func _on_enemy_entered(area: Area2D) -> void: ##registers one target per caldera and shares a single slow across overlapping fields
	if not is_instance_valid(_island) or unit.disabled:
		return
	var hitbox := area as Hitbox
	if not is_instance_valid(hitbox) or not is_instance_valid(hitbox.unit):
		return
	var enemy: Unit = hitbox.unit
	if enemy.hitbox != hitbox or enemy is Tower or not enemy.hostile or enemy.is_queued_for_deletion() or not is_instance_valid(enemy.modifiers_component):
		return
	var target_id: int = enemy.get_instance_id()
	if _targets.has(target_id):
		return
	_targets[target_id] = weakref(enemy)
	enemy.tree_exiting.connect(_remove_target.bind(target_id), CONNECT_ONE_SHOT)
	if enemy.has_meta(LAVA_SLOW_META):
		var shared_slow: LavaSlow = enemy.get_meta(LAVA_SLOW_META) as LavaSlow
		shared_slow.owners += 1
		return
	var slow := LavaSlow.new()
	slow.owners = 1
	slow.modifier = Modifier.new(Attributes.id.MAX_SPEED, LAVA_SPEED_MULTIPLIER, 0.0, -1.0, null, unit.unit_id)
	enemy.set_meta(LAVA_SLOW_META, slow)
	enemy.modifiers_component.add_modifier(slow.modifier)

func _on_enemy_exited(area: Area2D) -> void: ##drops the target after its hitbox leaves the combined detector
	var hitbox := area as Hitbox
	if is_instance_valid(hitbox) and is_instance_valid(hitbox.unit) and hitbox.unit.hitbox == hitbox:
		_remove_target(hitbox.unit.get_instance_id())

func _remove_target(target_id: int) -> void: ##releases only this caldera's claim and removes the slow on the last exit
	var target_ref: WeakRef = _targets.get(target_id)
	if target_ref == null:
		return
	_targets.erase(target_id)
	var enemy: Unit = target_ref.get_ref() as Unit
	if not is_instance_valid(enemy):
		return
	var exit_callback: Callable = _remove_target.bind(target_id)
	if enemy.tree_exiting.is_connected(exit_callback):
		enemy.tree_exiting.disconnect(exit_callback)
	if not enemy.has_meta(LAVA_SLOW_META):
		return
	var slow: LavaSlow = enemy.get_meta(LAVA_SLOW_META) as LavaSlow
	slow.owners -= 1
	if slow.owners > 0:
		return
	enemy.remove_meta(LAVA_SLOW_META)
	if is_instance_valid(enemy.modifiers_component):
		enemy.modifiers_component.remove_modifier(slow.modifier)

func update(_delta: float) -> void: ##spends one cooldown on one logical attack across the locally registered enemies
	if _targets.is_empty() or not _is_attack_possible(false) or not is_instance_valid(_island) or _island.game_ending:
		return
	var attack_context: AttackComponent.AttackLineageContext = attack_component.pull_attack_context()
	if not is_instance_valid(attack_context):
		return
	attack_context.use_attack_id_override = true
	attack_context.attack_id_override = AttackComponent.get_next_attack_id()
	var impact: VFXInfo = attack_component.attack_data.vfx_on_impact
	var primary: bool = true
	for target_id: int in _targets.keys():
		if unit.disabled:
			break
		var target_ref: WeakRef = _targets.get(target_id)
		var enemy: Unit = target_ref.get_ref() as Unit if target_ref != null else null
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			_remove_target(target_id)
			continue
		var impact_position: Vector2 = enemy.global_position
		attack_component.attack_with_context(enemy, attack_context, Vector2.ZERO, primary, primary)
		primary = false
		if is_instance_valid(impact):
			VFXManager.play_aoe_field(impact, impact_position, impact.radius)

func draw_visuals(_canvas: RangeIndicator) -> void: ##uses the lava cell highlights as the attack area display
	pass

func get_tower_influences(_candidate: Tower = null) -> Array[TowerInfluence]: ##highlights the exact lava coverage on a live tower or positioned preview
	if not is_instance_valid(unit) or not is_instance_valid(Run.references) or not is_instance_valid(Run.references.island):
		return []
	var cells: Array[Vector2i] = _get_covered_cells(unit as Tower, Run.references.island)
	if cells.is_empty():
		return []
	return [TowerInfluence.for_cells(&"caldera_lava", TowerInfluence.Kind.ATTACK, cells, null, [], false, TowerInfluence.Scope.WORLD)]
