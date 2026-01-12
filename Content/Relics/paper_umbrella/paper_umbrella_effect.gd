extends EffectPrototype
class_name PaperUmbrellaEffect

@export var cooldown_duration: float = 5.0 ## seconds between blocks per tower
#@export var shield_vfx_id: StringName = ID.Particles.SHIELD_BREAK ## Optional visual feedback

class UmbrellaState extends RefCounted:
	# if value <= 0.0, shield is ready.
	var tower_cooldowns: Dictionary[Tower, float] = {}

func _init() -> void:
	# PRE_HIT_RECEIVED: to block damage
	# TOWER_BUILT: to register new towers
	event_hooks = [GameEvent.EventType.HIT_RECEIVED, GameEvent.EventType.TOWER_BUILT, GameEvent.EventType.WAVE_STARTED]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = UmbrellaState.new()
	return instance

func _handle_attach(instance: EffectInstance) -> void:
	var state := instance.state as UmbrellaState
	# initial scan
	var all_towers: Array = References.get_tree().get_nodes_in_group(References.TOWER_GROUP)
	for t in all_towers:
		if t is Tower:
			state.tower_cooldowns[t] = 0.0
			_apply_shield_visual(t, true)
			
			t.tree_exiting.connect(func():
				state.tower_cooldowns.erase(t),
				CONNECT_ONE_SHOT
			)

func _handle_detach(instance: EffectInstance) -> void:
	var state := instance.state as UmbrellaState
	
	# Cleanup visuals
	for t in state.tower_cooldowns:
		if is_instance_valid(t):
			_apply_shield_visual(t, false)
	state.tower_cooldowns.clear()

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	var state := instance.state as UmbrellaState
	
	# register new towers
	if event.event_type == GameEvent.EventType.TOWER_BUILT:
		var data := event.data as BuildTowerData
		if data and is_instance_valid(data.tower):
			if not state.tower_cooldowns.has(data.tower):
				state.tower_cooldowns[data.tower] = 0.0
				_apply_shield_visual(data.tower, true)
				
				data.tower.tree_exiting.connect(func():
					state.tower_cooldowns.erase(data.tower),
					CONNECT_ONE_SHOT
				)
		return
		
	# reset cooldowns at the start of each wave
	if event.event_type == GameEvent.EventType.WAVE_STARTED:
		for tower: Tower in state.tower_cooldowns:
			state.tower_cooldowns[tower] = 0.0 #reset cooldown

	# block damage
	elif event.event_type == GameEvent.EventType.HIT_RECEIVED:
		# Check if the victim is a registered tower
		var victim: Tower = event.unit as Tower
		if not victim or not state.tower_cooldowns.has(victim):
			return
			
		var timer: float = state.tower_cooldowns[victim]
		
		# if shield is ready (timer <= 0)
		if timer <= 0.0:
			var hit_data := event.data as HitData
			hit_data.negate = true
			state.tower_cooldowns[victim] = cooldown_duration
			
			# visual Feedback
			_apply_shield_visual(victim, false)

func on_tick(instance: EffectInstance, delta: float) -> void:
	var state := instance.state as UmbrellaState
	
	var towers_to_remove: Array[Tower] = []

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
#
	#var mat = tower.graphics.material as ShaderMaterial
	#if mat:
		## Just a subtle paper-white tint when active
		#var tint = Color(1.0, 1.0, 0.9, 0.3) if is_active else Color.TRANSPARENT
		## mat.set_shader_parameter("shield_tint", tint) # If you add this to unit shader
