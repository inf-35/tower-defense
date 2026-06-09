extends EffectPrototype
class_name PaperUmbrellaEffect

@export var cooldown_duration: float = 5.0 ##seconds between blocks per tower

class UmbrellaState extends RefCounted:
	#if value <= 0.0, shield is ready.
	var tower_cooldowns: Dictionary[Tower, float] = {}

func _init() -> void:
	#pre_hit_received: to block damage
	#tower_built: to register new towers
	event_hooks = [
		GameEvent.EventType.HIT_RECEIVED,
		GameEvent.EventType.TOWER_BUILT,
		GameEvent.EventType.WAVE_PREP_STARTED,
		GameEvent.EventType.WAVE_STARTED,
		GameEvent.EventType.WAVE_ENDED,
	]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = UmbrellaState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	var state: UmbrellaState = instance.state as UmbrellaState
	#initial scan
	var all_towers: Array = Run.references.get_tree().get_nodes_in_group(Run.references.TOWER_GROUP)
	for t in all_towers:
		if t is Tower:
			state.tower_cooldowns[t] = 0.0
			_apply_shield_visual(t, true)

			t.tree_exiting.connect(func():
				state.tower_cooldowns.erase(t),
				CONNECT_ONE_SHOT
			)

func _handle_detach(instance: EffectInstance) -> void:
	var state: UmbrellaState = instance.state as UmbrellaState

	#cleanup visuals
	for t in state.tower_cooldowns:
		if is_instance_valid(t):
			_apply_shield_visual(t, false)
	state.tower_cooldowns.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	var state: UmbrellaState = instance.state as UmbrellaState

	#register new towers
	if event.event_type == GameEvent.EventType.TOWER_BUILT:
		var data: BuildTowerData = event.data as BuildTowerData
		if data and is_instance_valid(data.tower):
			if not state.tower_cooldowns.has(data.tower):
				state.tower_cooldowns[data.tower] = 0.0
				_apply_shield_visual(data.tower, true)

				data.tower.tree_exiting.connect(func():
					state.tower_cooldowns.erase(data.tower),
					CONNECT_ONE_SHOT
				)
		return

	if event.event_type == GameEvent.EventType.WAVE_PREP_STARTED or event.event_type == GameEvent.EventType.WAVE_STARTED or event.event_type == GameEvent.EventType.WAVE_ENDED:
		for tower: Tower in state.tower_cooldowns:
			state.tower_cooldowns[tower] = 0.0
			_apply_shield_visual(tower, true)

	#block damage
	elif event.event_type == GameEvent.EventType.HIT_RECEIVED:
		#check if the victim is a registered tower
		var victim: Tower = event.unit as Tower
		if not victim or not state.tower_cooldowns.has(victim):
			return

		var timer: float = state.tower_cooldowns[victim]

		#if shield is ready (timer <= 0)
		if timer <= 0.0:
			var hit_data: HitData = event.data as HitData
			hit_data.negate = true
			state.tower_cooldowns[victim] = cooldown_duration

			#visual feedback
			_apply_shield_visual(victim, false)

func on_tick(instance: EffectInstance, delta: float) -> void:
	var state: UmbrellaState = instance.state as UmbrellaState

	for tower: Tower in state.tower_cooldowns:
		if not is_instance_valid(tower):
			continue

		var timer: float = state.tower_cooldowns[tower]

		if timer > 0.0:
			timer -= delta
			state.tower_cooldowns[tower] = timer

			if timer <= 0.0:
				_apply_shield_visual(tower, true)

func _apply_shield_visual(tower: Tower, is_active: bool) -> void:
	if not is_instance_valid(tower) or not is_instance_valid(tower.graphics):
		return
