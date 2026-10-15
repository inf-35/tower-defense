extends EffectPrototype
class_name SpareSuppliesEffect

@export_range(0.1, 100.0, 0.1, "or_greater") var restored_health: float = 6.0 ##health restored when a lethal loss consumes this relic
@export var activation_scene: PackedScene = preload("res://Content/Relics/spare_supplies/spare_supplies_activation.tscn") ##local paused icon flight and particle burst; gameplay resolves at its burst signal

class SuppliesState extends RefCounted:
	var activating: bool = false
	var activated: bool = false
	var waves: Waves
	var activation: SpareSuppliesActivation

func _init() -> void:
	global = true
	event_hooks = [GameEvent.EventType.PLAYER_HEALTH_LOSS]

func create_instance() -> EffectInstance:
	var instance: EffectInstance = return_generic_instance()
	instance.state = SuppliesState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void: ##tracks deferred enemies only while this relic is owned
	var state := instance.state as SuppliesState
	state.waves = Run.waves
	state.waves.enemy_spawned.connect(_register_enemy_death_tracking.bind(state))

func _handle_detach(instance: EffectInstance) -> void: ##releases the spawn listener unless activation is still clearing death reactions
	var state := instance.state as SuppliesState
	if is_instance_valid(state.activation):
		state.activation.cancel()
	if not is_instance_valid(state.waves) or state.activated:
		return
	state.waves.enemy_spawned.disconnect(_register_enemy_death_tracking.bind(state))

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##intercepts lethal loss and reserves this one-use rescue before any follow-up events
	if Run.phases.is_game_over:
		return
	var health_loss := event.data as PlayerHealthLossData
	if health_loss == null:
		return
	var state := instance.state as SuppliesState
	if state.activating:
		#already-queued keep collisions must not kill the player during the paused reveal.
		health_loss.health_after = health_loss.health_before
		return
	if state.activated:
		return
	if health_loss.health_after > 0.0 and not is_zero_approx(health_loss.health_after):
		return

	health_loss.health_after = health_loss.health_before
	state.activating = true
	health_loss.resolved.connect(_begin_activation.bind(Run.player, Run.waves, state), CONNECT_ONE_SHOT)

func _begin_activation(player: Player, waves: Waves, state: SuppliesState) -> void: ##starts the relic-owned presentation after the intercepted loss has settled
	var activation := activation_scene.instantiate() as SpareSuppliesActivation
	state.activation = activation
	activation.burst.connect(_activate.bind(player, waves, state), CONNECT_ONE_SHOT)
	activation.cancelled.connect(func() -> void:
		state.activating = false
		state.activation = null
	, CONNECT_ONE_SHOT)
	Run.references.island.add_child(activation)
	activation.play(icon, RelicData.Type.SPARE_SUPPLIES)

func _activate(player: Player, waves: Waves, state: SuppliesState) -> void: ##consumes the relic and completes combat only after its own enemy cleanup finishes
	state.activating = false
	state.activated = true
	state.activation = null
	var ended_wave: int = waves.stop_combat_wave()
	player.hp = restored_health
	player.remove_relic_by_type(RelicData.Type.SPARE_SUPPLIES)
	_clear_non_boss_enemies(waves)
	waves.enemy_spawned.disconnect(_register_enemy_death_tracking.bind(state))
	if is_instance_valid(Run.boss_encounters) and Run.boss_encounters.has_active_encounter():
		Run.boss_encounters.end_current_subwave()
	elif ended_wave > 0:
		waves.wave_ended.emit(ended_wave)

func _clear_non_boss_enemies(waves: Waves) -> void: ##kills live non-boss enemies through their normal death notifications
	for enemy: Unit in waves.get_tree().get_nodes_in_group(Waves.ENEMY_GROUP):
		if enemy.is_queued_for_deletion() or enemy.has_meta(ID.UnitMeta.IS_BOSS):
			continue
		if is_instance_valid(enemy.health_component):
			enemy.health_component.health = 0.0
		var hit_report := HitReportData.new()
		hit_report.real = false
		hit_report.target = enemy
		hit_report.death_caused = true
		enemy.died.emit(hit_report)

func _register_enemy_death_tracking(unit: Unit, state: SuppliesState) -> void: ##retires pending spawns if this relic clears combat before they enter the scene
	unit.ready.connect(func() -> void:
		if state.activated and not unit.has_meta(ID.UnitMeta.IS_BOSS):
			unit.queue_free()
	, CONNECT_ONE_SHOT)
