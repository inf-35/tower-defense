extends EffectPrototype
class_name EarlyBirdEffect

# --- Configuration ---
@export var modifiers: Array[ModifierDataPrototype] = [] ##modifiers applied to the first tower that hits something

# --- State Strategy ---
class EarlyBirdState extends RefCounted:
	var triggered_this_wave: bool = false
	var early_bird: Tower
	var active_modifiers: Array[Modifier] = [] # Track active buffs to clear them later

func _init() -> void:
	event_hooks = [
		GameEvent.EventType.WAVE_STARTED, 
		GameEvent.EventType.HIT_DEALT, 
		GameEvent.EventType.WAVE_ENDED
	]
	global = true

func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	instance.state = EarlyBirdState.new()
	return instance

func _handle_attach(_i: EffectInstance) -> void: pass
func _handle_detach(_i: EffectInstance) -> void: pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	var state := instance.state as EarlyBirdState
	
	match event.event_type:
		GameEvent.EventType.WAVE_STARTED:
			# reset trigger flag
			state.triggered_this_wave = false
			
		GameEvent.EventType.HIT_DEALT:
			# if already triggered, ignore all hits
			if state.triggered_this_wave:
				return

			var attacker: Unit = event.unit
			# attacker must be an allied tower
			if (not is_instance_valid(attacker)) or not attacker is Tower:
				return
			
			if attacker.hostile:
				return
			
			if Phases.current_phase != Phases.GamePhase.COMBAT_WAVE:
				return

			state.triggered_this_wave = true
			_apply_buff(state, attacker as Tower)
			
			# Visual Feedback
			#VFXManager.play_vfx(ID.Particles.LEVEL_UP, attacker.global_position, Vector2.UP)
			
		GameEvent.EventType.WAVE_ENDED:
			# remove buffs (cleanup)
			_clear_buffs(state)

func _apply_buff(state: EarlyBirdState, tower: Tower) -> void:
	if not is_instance_valid(tower.modifiers_component):
		return
	
	var early_bird_state := state as EarlyBirdState
	early_bird_state.early_bird = tower
	
	if not tower.modifiers_component:
		return

	for modifier_prototype in modifiers:
		var modifier: Modifier = modifier_prototype.generate_modifier()
		tower.modifiers_component.add_modifier(modifier)
		early_bird_state.active_modifiers.append(modifier)
	
func _clear_buffs(state: EarlyBirdState) -> void:
	var early_bird_state := state as EarlyBirdState
	var tower := early_bird_state.early_bird
	
	if is_instance_valid(tower) and is_instance_valid(tower.modifiers_component):
		for mod in state.active_modifiers:
			tower.modifiers_component.remove_modifier(mod)
			
	early_bird_state.active_modifiers.clear()
	early_bird_state.early_bird = null
