extends Node

enum GameDifficulty {
	NORMAL,
	HARD,
}

enum GameEnvironment {
	WOODS,
	WINTER,
}

const REFERENCES_SCRIPT := preload("res://Singletons/references.gd")
const PLAYER_SCRIPT := preload("res://Singletons/player.gd")
const WAVES_SCRIPT := preload("res://Singletons/waves.gd")
const PHASES_SCRIPT := preload("res://Singletons/phase_manager.gd")
const POWER_SERVICE_SCRIPT := preload("res://Singletons/power_service.gd")
const DAMAGE_TRACKER_SERVICE_SCRIPT := preload("res://Singletons/damage_tracker_service.gd")

var _run_root: Node
var _run_owner: Island
var _run_generation: int = 0
var _is_run_ready: bool = false

var pending_game_difficulty: GameDifficulty = GameDifficulty.NORMAL
var current_game_difficulty: GameDifficulty = GameDifficulty.NORMAL
var current_game_scaling: float = 1.0
var current_game_environment: GameEnvironment = GameEnvironment.WOODS

var references: References
var player: Player
var waves: Waves
var phases: Phases
var power_service: PowerService
var damage_tracker: DamageTrackerService

signal references_ready ##emitted once the current run is fully booted and safe to use

func has_active_run() -> bool:
	return is_instance_valid(_run_root)

func is_run_ready() -> bool:
	return _is_run_ready

func begin_run(island: Island) -> void:
	end_run()
	_run_generation += 1
	_run_owner = island
	_is_run_ready = false

	_run_root = Node.new()
	_run_root.name = "RunState"
	add_child(_run_root)

	references = REFERENCES_SCRIPT.new()
	player = PLAYER_SCRIPT.new()
	waves = WAVES_SCRIPT.new()
	phases = PHASES_SCRIPT.new()
	power_service = POWER_SERVICE_SCRIPT.new()
	damage_tracker = DAMAGE_TRACKER_SERVICE_SCRIPT.new()

	_run_root.add_child(references)
	_run_root.add_child(player)
	_run_root.add_child(waves)
	_run_root.add_child(phases)
	_run_root.add_child(power_service)
	_run_root.add_child(damage_tracker)

	current_game_difficulty = pending_game_difficulty
	current_game_scaling = 1.0
	current_game_environment = GameEnvironment.WOODS

	island.tree_exited.connect(_on_run_owner_tree_exited.bind(_run_generation), CONNECT_ONE_SHOT)
	_prime_run_references.call_deferred(island, _run_generation)

func finalize_run_setup() -> void:
	if _is_run_ready or not has_active_run():
		return
	if is_instance_valid(references) and not references.is_ready:
		await references.internal_references_ready
	if not has_active_run():
		return
	_is_run_ready = true
	references_ready.emit()

func end_run() -> void:
	_clear_run_handles()
	
	current_game_scaling = 1.0
	current_game_environment = GameEnvironment.WOODS

func set_pending_game_difficulty(game_difficulty: GameDifficulty) -> void:
	pending_game_difficulty = game_difficulty
	current_game_difficulty = game_difficulty

func get_save_data() -> Dictionary:
	return {
		"pending_game_difficulty": int(pending_game_difficulty),
		"current_game_difficulty": int(current_game_difficulty),
		"current_game_scaling": current_game_scaling,
		"current_game_environment": int(current_game_environment),
	}

func load_save_data(data: Dictionary) -> void:
	pending_game_difficulty = int(data.get("pending_game_difficulty", GameDifficulty.NORMAL))
	current_game_difficulty = int(data.get("current_game_difficulty", pending_game_difficulty))
	current_game_scaling = float(data.get("current_game_scaling", 1.0))
	current_game_environment = int(data.get("current_game_environment", GameEnvironment.WOODS))

func _prime_run_references(island: Island, run_generation: int) -> void:
	if run_generation != _run_generation:
		return
	if not is_instance_valid(references):
		return
	references.start(island)
	power_service.register_island(island)

func _on_run_owner_tree_exited(run_generation: int) -> void:
	if run_generation != _run_generation:
		return
	end_run()

func _clear_run_handles() -> void:
	if _run_root: _run_root.free()
	_run_root = null
	
	_is_run_ready = false
	_run_owner = null
	references = null
	player = null
	waves = null
	phases = null
	power_service = null
	damage_tracker = null
