extends Node
class_name BossEncounterService

const BossEncounters := preload("res://Indexes/boss_encounters.gd")

signal subwave_started(wave_number: int, subwave_index: int) ##emitted when one boss combat segment begins
signal subwave_cleared(wave_number: int, subwave_index: int) ##emitted when prep should begin without advancing the displayed wave
signal encounter_ended(wave_number: int, encounter_type: int) ##emitted when the boss dies or the encounter otherwise fully ends

const BOSS_FOOTPRINT_RADIUS: int = 0
const DEFAULT_SPAWN_STAGGER_WINDOW: float = 5.0

var active_encounter_type: BossEncounters.Type = BossEncounters.Type.NONE
var active_wave_number: int = 0

var _encounter_data: BossEncounterData
var _logic: BossEncounterLogic
var _context: BossEncounterContext
var _boss: Unit
var _active_minions: Array[Unit] = []
var _subwave_index: int = 0
var _subwave_elapsed: float = 0.0
var _planned_minions_spawned: bool = false
var _subwave_active: bool = false
var _ending_encounter: bool = false
var _spawn_generation: int = 0
var _boss_frozen: bool = false
var _boss_saved_collision_layer: int = 0
var _boss_saved_collision_mask: int = 0
var _boss_saved_disabled: bool = false
var _boss_freeze_applied: bool = false
var _pending_loaded_health: float = -1.0
var _pending_logic_save_data: Dictionary = {}

func _ready() -> void:
	set_process(false)

func _exit_tree() -> void:
	TerrainService.release_build_reservations(self)

func start() -> void: ##clears any stale encounter state when a new run starts
	UI.boss_encounter_ended.emit()
	_clear_runtime_state()
	TerrainService.release_build_reservations(self)

func get_boss() -> Unit: ##returns the active persistent boss unit, if any
	return _boss if is_instance_valid(_boss) else null

func get_subwave_index() -> int: ##returns the zero-based current or next subwave index
	return _subwave_index

func get_subwave_elapsed() -> float: ##returns elapsed combat time for the active subwave
	return _subwave_elapsed

func has_active_encounter() -> bool: ##returns whether a boss encounter is currently loaded into the run
	return active_encounter_type != BossEncounters.Type.NONE

func is_active_boss(unit: Unit) -> bool: ##checks whether the supplied unit is this service's persistent boss
	return is_instance_valid(unit) and is_instance_valid(_boss) and unit == _boss

func suppresses_boss_hits(unit: Unit) -> bool: ##returns whether late projectiles or direct hits should be ignored during boss prep
	return _boss_frozen and is_active_boss(unit)

func get_preview_enemy_stacks() -> Array[Array]: ##returns boss preview plus the next subwave's minions for existing breach preview UI
	if active_encounter_type == BossEncounters.Type.NONE:
		return []
	return BossEncounters.get_preview_enemy_stacks(active_encounter_type, _subwave_index, true)

func start_or_resume_subwave(wave_number: int, encounter_type: BossEncounters.Type) -> void: ##starts a new encounter or resumes the next subwave of the active one
	if encounter_type == BossEncounters.Type.NONE:
		push_warning("BossEncounterService: Cannot start NONE encounter.")
		return

	if has_active_encounter() and (active_wave_number != wave_number or active_encounter_type != encounter_type):
		push_warning("BossEncounterService: Different boss encounter requested while one is active.")
		return

	if not has_active_encounter():
		_begin_encounter(wave_number, encounter_type)

	_start_current_subwave()

func spawn_minion(unit_type: Units.Type, position: Vector2) -> Unit: ##spawns one minion on normal targeting layers without touching ordinary wave counters
	var minion: Unit = Run.waves.spawn_enemy(unit_type, position, false)
	if not is_instance_valid(minion):
		return null

	if minion.is_ready:
		_track_minion(minion)
	else:
		minion.ready.connect(_track_minion.bind(minion), CONNECT_ONE_SHOT)
	return minion

func fail_boss_reached_keep() -> void: ##ends the run immediately when the active boss reaches the keep
	if _ending_encounter:
		return
	_ending_encounter = true
	if is_instance_valid(Run.phases):
		Run.phases.start_game_over(false)

func get_save_data() -> Dictionary: ##serializes prep-safe boss encounter state for save/load
	if not has_active_encounter() or not is_instance_valid(_boss):
		return {
			"active": false,
		}

	var boss_health: float = 0.0
	if is_instance_valid(_boss.health_component):
		boss_health = _boss.health_component.health

	return {
		"active": true,
		"encounter_type": int(active_encounter_type),
		"wave_number": active_wave_number,
		"subwave_index": _subwave_index,
		"boss_type": int(_encounter_data.boss_type) if _encounter_data != null else int(_boss.enemy_type),
		"boss_position": [_boss.global_position.x, _boss.global_position.y],
		"boss_health": boss_health,
		"frozen": _boss_frozen,
		"logic": _logic.get_save_data() if _logic != null else {},
	}

func load_save_data(data: Dictionary) -> void: ##restores an active boss encounter saved during boss prep
	_clear_runtime_state()
	if not bool(data.get("active", false)):
		return

	active_encounter_type = int(data.get("encounter_type", BossEncounters.Type.NONE))
	if active_encounter_type == BossEncounters.Type.NONE:
		_clear_runtime_state()
		return

	active_wave_number = int(data.get("wave_number", 0))
	_subwave_index = int(data.get("subwave_index", 0))
	_encounter_data = BossEncounters.get_encounter_data(active_encounter_type)
	if _encounter_data == null:
		_clear_runtime_state()
		return

	_context = BossEncounterContext.new(self)
	_logic = _encounter_data.create_logic()
	_logic.initialise(_context)
	_pending_logic_save_data = data.get("logic", {})
	_logic.load_save_data(_pending_logic_save_data)

	var position_data: Array = data.get("boss_position", [0.0, 0.0])
	var boss_position := Vector2(float(position_data[0]), float(position_data[1]))
	_pending_loaded_health = float(data.get("boss_health", -1.0))
	_spawn_boss(boss_position)
	_freeze_boss_for_prep()
	UI.boss_encounter_started.emit(_encounter_data.title, _boss)
	UI.boss_subwave_changed.emit(_subwave_index + 1)

func _process(_delta: float) -> void:
	if not _subwave_active or _ending_encounter:
		return

	var delta: float = Clock.game_delta
	_subwave_elapsed += delta
	if _logic != null:
		_logic.update_subwave(_context, delta)
	_check_subwave_clear()

func _begin_encounter(wave_number: int, encounter_type: BossEncounters.Type) -> void: ##creates encounter runtime state and spawns the persistent boss once
	active_wave_number = wave_number
	active_encounter_type = encounter_type
	_encounter_data = BossEncounters.get_encounter_data(encounter_type)
	if _encounter_data == null:
		push_error("BossEncounterService: Encounter data missing.")
		_clear_runtime_state()
		return

	_context = BossEncounterContext.new(self)
	_logic = _encounter_data.create_logic()
	_logic.initialise(_context)
	_subwave_index = 0
	_ending_encounter = false

	_spawn_boss(_get_initial_boss_spawn_position())
	UI.boss_encounter_started.emit(_encounter_data.title, _boss)
	UI.boss_subwave_changed.emit(_subwave_index + 1)
	if _logic != null:
		_logic.on_encounter_started(_context)

func _spawn_boss(position: Vector2) -> void: ##spawns the persistent boss on normal enemy hitbox layers while exempting it from wave counters
	_boss = Run.waves.spawn_enemy(_encounter_data.boss_type, position, false)
	if not is_instance_valid(_boss):
		push_error("BossEncounterService: Failed to spawn boss.")
		return

	_boss.set_meta(ID.UnitMeta.IS_BOSS, true)
	_boss.set_meta(ID.UnitMeta.BOSS_ENCOUNTER_TYPE, int(active_encounter_type))
	_boss.changed_cell.connect(_on_boss_changed_cell)
	_boss.ready.connect(_on_boss_ready, CONNECT_ONE_SHOT)

func _on_boss_ready() -> void: ##binds healthbar updates once the boss components have entered the tree
	if not is_instance_valid(_boss):
		return

	if not _boss.died.is_connected(_on_boss_died):
		_boss.died.connect(_on_boss_died, CONNECT_ONE_SHOT)

	if is_instance_valid(_boss.health_component):
		if _pending_loaded_health >= 0.0:
			_boss.health_component.health = _pending_loaded_health
			_pending_loaded_health = -1.0
		_boss.health_component.health_changed.connect(func(_health: float): _emit_boss_health())
		_emit_boss_health()

	if _boss_frozen and not _boss_freeze_applied:
		_apply_freeze_to_boss()

func _start_current_subwave() -> void: ##resumes boss combat and begins spawning the current subwave's minion packet
	if not is_instance_valid(_boss):
		push_error("BossEncounterService: Cannot start subwave without a boss.")
		return

	var subwave: BossSubwaveData = _encounter_data.get_subwave(_subwave_index)
	if subwave == null:
		push_warning("BossEncounterService: Encounter has no subwaves; ending as cleared.")
		_end_encounter()
		return

	_release_boss_from_prep()
	_active_minions.clear()
	_subwave_elapsed = 0.0
	_planned_minions_spawned = false
	_subwave_active = true
	_spawn_generation += 1
	set_process(true)

	UI.boss_subwave_changed.emit(_subwave_index + 1)
	Run.waves.wave_started.emit(active_wave_number)
	subwave_started.emit(active_wave_number, _subwave_index + 1)
	if _logic != null:
		_logic.on_boss_resumed_for_combat(_context)
		_logic.on_subwave_started(_context)

	_spawn_minions_for_subwave(subwave, _spawn_generation)

func _spawn_minions_for_subwave(subwave: BossSubwaveData, spawn_generation: int) -> void: ##spreads boss minion spawns across the same breach cycle style as ordinary waves
	var total_minions: int = subwave.get_enemy_count()
	if total_minions <= 0:
		_planned_minions_spawned = true
		_check_subwave_clear()
		return

	var enemy_stagger: float = DEFAULT_SPAWN_STAGGER_WINDOW / float(total_minions)
	var spawn_sequence_index: int = 0
	for enemy_stack: Array in subwave.get_enemy_stacks():
		if enemy_stack.size() < 2:
			continue
		var unit_type: Units.Type = enemy_stack[0]
		var unit_stack_count: int = int(enemy_stack[1])
		for _stack_index: int in range(unit_stack_count):
			if spawn_generation != _spawn_generation or not _subwave_active or _ending_encounter:
				return

			var breach: Tower = Run.waves.get_breach_for_spawn_index(spawn_sequence_index)
			if not is_instance_valid(breach):
				push_warning("BossEncounterService: No active breaches found for boss minions.")
				_planned_minions_spawned = true
				_check_subwave_clear()
				return

			spawn_minion(unit_type, Island.cell_to_position(breach.tower_position))
			spawn_sequence_index += 1
			await Clock.await_game_time(enemy_stagger * 0.6)

		await Clock.await_game_time(enemy_stagger * 0.8)

	_planned_minions_spawned = true
	_check_subwave_clear()

func _track_minion(minion: Unit) -> void: ##registers one spawned boss minion against the current subwave clear condition
	if not is_instance_valid(minion):
		return

	_active_minions.append(minion)
	minion.set_meta(ID.UnitMeta.BOSS_MINION_ENCOUNTER_TYPE, int(active_encounter_type))
	minion.died.connect(func(_hit_report_data: HitReportData): _on_minion_removed(minion), CONNECT_ONE_SHOT)
	minion.tree_exiting.connect(func(): _on_minion_removed(minion), CONNECT_ONE_SHOT)

func _on_minion_removed(minion: Unit) -> void: ##forgets dead or freed minions and checks whether the subwave can clear
	_active_minions.erase(minion)
	if _ending_encounter:
		return
	_check_subwave_clear()

func _check_subwave_clear() -> void: ##ends the current subwave only after minions, spawning, and mandatory time are all satisfied
	if not _subwave_active or _ending_encounter:
		return
	if not _planned_minions_spawned:
		return

	_prune_invalid_minions()
	if not _active_minions.is_empty():
		return

	var subwave: BossSubwaveData = _encounter_data.get_subwave(_subwave_index)
	var mandatory_duration: float = subwave.mandatory_duration if subwave != null else 0.0
	if _subwave_elapsed < mandatory_duration:
		return

	_clear_current_subwave()

func _clear_current_subwave() -> void: ##freezes the boss and asks phases to enter prep without advancing the wave number
	_subwave_active = false
	set_process(false)
	_spawn_generation += 1

	if _logic != null:
		_logic.on_subwave_cleared(_context)

	var cleared_subwave_index: int = _subwave_index + 1
	_subwave_index += 1
	_freeze_boss_for_prep()
	UI.boss_subwave_changed.emit(_subwave_index + 1)
	subwave_cleared.emit(active_wave_number, cleared_subwave_index)

func _freeze_boss_for_prep() -> void: ##keeps the boss visible but removes movement, targeting, damageability, and status ticking for prep
	_boss_frozen = true
	_apply_freeze_to_boss()
	_reserve_boss_cells()
	if _logic != null:
		_logic.on_boss_frozen_for_prep(_context)

func _apply_freeze_to_boss() -> void: ##applies freeze flags defensively because loading can call this before boss ready
	if not is_instance_valid(_boss):
		return
	if _boss_freeze_applied:
		return

	_boss_saved_disabled = _boss.disabled
	_boss.disabled = true

	if is_instance_valid(_boss.movement_component):
		_boss.movement_component.paused = true
	if is_instance_valid(_boss.health_component):
		_boss.health_component.set_process(false)
	if is_instance_valid(_boss.modifiers_component):
		_boss.modifiers_component.set_status_timers_paused(true)
	if is_instance_valid(_boss.hitbox):
		_boss_saved_collision_layer = _boss.hitbox.collision_layer
		_boss_saved_collision_mask = _boss.hitbox.collision_mask
		_boss.hitbox.collision_layer = 0
		_boss.hitbox.collision_mask = 0
	_boss_freeze_applied = true

func _release_boss_from_prep() -> void: ##restores combat collision, movement, status timers, and behavior updates for the next subwave
	TerrainService.release_build_reservations(self)
	_boss_frozen = false
	if not _boss_freeze_applied:
		return
	if not is_instance_valid(_boss):
		return

	_boss.disabled = _boss_saved_disabled
	if is_instance_valid(_boss.movement_component):
		_boss.movement_component.paused = false
	if is_instance_valid(_boss.health_component):
		_boss.health_component.set_process(true)
	if is_instance_valid(_boss.modifiers_component):
		_boss.modifiers_component.set_status_timers_paused(false)
	if is_instance_valid(_boss.hitbox):
		_boss.hitbox.collision_layer = _boss_saved_collision_layer
		_boss.hitbox.collision_mask = _boss_saved_collision_mask
	_boss_freeze_applied = false

func _on_boss_changed_cell(_old_cell: Vector2i, _new_cell: Vector2i) -> void: ##keeps the prep build reservation under the boss as it persists across subwaves
	if _boss_frozen:
		_reserve_boss_cells()

func _reserve_boss_cells() -> void: ##reserves the boss footprint against player construction while prep is active
	if not is_instance_valid(_boss) or not is_instance_valid(_boss.movement_component):
		return

	var cells: Array[Vector2i] = []
	var center_cell: Vector2i = _boss.movement_component.cell_position
	for x: int in range(-BOSS_FOOTPRINT_RADIUS, BOSS_FOOTPRINT_RADIUS + 1):
		for y: int in range(-BOSS_FOOTPRINT_RADIUS, BOSS_FOOTPRINT_RADIUS + 1):
			cells.append(center_cell + Vector2i(x, y))
	TerrainService.reserve_build_cells(self, cells, "Boss occupies this tile")

func _on_boss_died(_hit_report_data: HitReportData) -> void: ##ends the entire encounter and removes remaining minions when the boss dies
	if _ending_encounter:
		return
	_ending_encounter = true
	if _logic != null:
		_logic.on_boss_died(_context)
	_kill_remaining_minions()
	_end_encounter()

func _kill_remaining_minions() -> void: ##uses normal death emission for cleanup while guarding against subwave-clear recursion
	var minions: Array[Unit] = _active_minions.duplicate()
	_active_minions.clear()
	for minion: Unit in minions:
		if not is_instance_valid(minion):
			continue
		var hit_report := HitReportData.new()
		hit_report.real = false
		minion.died.emit(hit_report)

func _end_encounter() -> void: ##releases encounter state and notifies phases that this real wave is complete
	var ended_wave: int = active_wave_number
	var ended_type: BossEncounters.Type = active_encounter_type
	TerrainService.release_build_reservations(self)
	UI.boss_encounter_ended.emit()
	_clear_runtime_state()
	encounter_ended.emit(ended_wave, ended_type)

func _clear_runtime_state() -> void: ##drops all local references without mutating unrelated ordinary wave state
	set_process(false)
	_spawn_generation += 1
	active_encounter_type = BossEncounters.Type.NONE
	active_wave_number = 0
	_encounter_data = null
	_logic = null
	_context = null
	_boss = null
	_active_minions.clear()
	_subwave_index = 0
	_subwave_elapsed = 0.0
	_planned_minions_spawned = false
	_subwave_active = false
	_ending_encounter = false
	_boss_frozen = false
	_boss_freeze_applied = false
	_pending_loaded_health = -1.0
	_pending_logic_save_data.clear()

func _emit_boss_health() -> void: ##pushes the authoritative boss health values into the HUD
	if not is_instance_valid(_boss) or not is_instance_valid(_boss.health_component):
		return
	UI.boss_health_changed.emit(_boss.health_component.max_health, _boss.health_component.health)

func _prune_invalid_minions() -> void: ##keeps freed minion references out of the subwave clear condition
	for i: int in range(_active_minions.size() - 1, -1, -1):
		if not is_instance_valid(_active_minions[i]):
			_active_minions.remove_at(i)

func _get_initial_boss_spawn_position() -> Vector2: ##spawns the boss from the active breach farthest from the keep for maximum pressure readability
	var active_breaches: Array[Tower] = SpawnPointService.get_active_breaches()
	var best_breach: Tower = null
	var best_distance: float = -1.0
	for breach: Tower in active_breaches:
		if not is_instance_valid(breach):
			continue
		var distance: float = _get_breach_keep_distance(breach)
		if distance > best_distance:
			best_distance = distance
			best_breach = breach

	if is_instance_valid(best_breach):
		return Island.cell_to_position(best_breach.tower_position)

	var spawn_points: Array[Vector2i] = SpawnPointService.get_spawn_points()
	if not spawn_points.is_empty():
		return Island.cell_to_position(spawn_points[0])

	var fallback_cell: Vector2i = _get_farthest_known_cell_from_keep()
	if fallback_cell != Vector2i.ZERO:
		return Island.cell_to_position(fallback_cell)
	return Vector2.ZERO

func _get_farthest_known_cell_from_keep() -> Vector2i: ##provides a non-lethal fallback for debug starts before breach data exists
	if not is_instance_valid(Run.references.island):
		return Vector2i.ZERO

	var keep_cell: Vector2i = _get_keep_cell()
	var best_cell: Vector2i = Vector2i.ZERO
	var best_distance_squared: float = -1.0
	for cell: Vector2i in Run.references.island.terrain_base_grid:
		var distance_squared: float = Vector2(cell - keep_cell).length_squared()
		if distance_squared <= best_distance_squared:
			continue
		best_distance_squared = distance_squared
		best_cell = cell
	return best_cell

func _get_keep_cell() -> Vector2i: ##returns the keep tile when available, otherwise uses the origin as a stable fallback
	if is_instance_valid(Run.references.keep) and Run.references.keep is Tower:
		var keep: Tower = Run.references.keep
		return keep.tower_position
	return Vector2i.ZERO

func _get_breach_keep_distance(breach: Tower) -> float: ##matches ordinary wave distance weighting in tile space without reaching into Waves internals
	if not is_instance_valid(breach):
		return 0.0
	if is_instance_valid(Run.references.keep) and Run.references.keep is Tower:
		return Vector2(breach.tower_position - _get_keep_cell()).length()
	return Vector2(breach.tower_position).length()
