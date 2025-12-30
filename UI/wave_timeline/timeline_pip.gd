extends Control
class_name TimelinePip

@export var animatable_wrapper: AnimatableUI
@export var icon_rect: TextureRect
@export var background_panel: Panel # for background color, if needed

@export var day_color: Color = Color("8cbf68") # Greenish
@export var combat_color: Color = Color("6891bf") # Blueish
@export var boss_color: Color = Color("bf6868") # Reddish

var target_slot: Control # the anchor node we should follow
var _entry: WaveTimeline.TimelineEntry
var _active_tooltip: TooltipPanel

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func setup(entry: WaveTimeline.TimelineEntry) -> void:
	_entry = entry
	var is_combat: bool = entry.is_combat
	var variant: int = entry.subtype
	
	# apply colors/icons based on type
	if is_combat:
		match variant:
			Phases.CombatVariant.BOSS:
				background_panel.self_modulate = boss_color
				icon_rect.texture = preload("res://Assets/normal_battle_phase.png")
			_:
				background_panel.self_modulate = combat_color
				icon_rect.texture = preload("res://Assets/normal_battle_phase.png")
	else:
		background_panel.self_modulate = day_color
		match variant:
			Phases.DayEvent.EXPANSION:
				icon_rect.texture = preload("res://Assets/expansion_phase_icon.png")
			_:
				pass # implement

	# enter scene (grow from nothign)
	if is_instance_valid(animatable_wrapper):
		animatable_wrapper.idle_sway_enabled = true
		animatable_wrapper.idle_random_phase = true
		animatable_wrapper.auto_play_entrance = true
		animatable_wrapper.scale = Vector2.ZERO 

func move_to_slot(slot: Control, duration: float = 0.5) -> void:
	target_slot = slot
	
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# tween global_position to match the slot's global_position
	tween.tween_property(self, "global_position", slot.global_position, duration)

	if is_instance_valid(animatable_wrapper):
		# scale icon up to normal size
		tween.parallel().tween_property(animatable_wrapper, "scale", Vector2.ONE, duration)

func fade_out_and_die() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(self, "scale", Vector2(0.5, 0.5), 0.3)
	tween.tween_callback(queue_free)
	
func _on_mouse_entered() -> void:
	if is_instance_valid(_active_tooltip):
		_active_tooltip.close()
	
	var title_text: String = ""
	var desc_text: String = ""
	
	if _entry.is_combat:
		# combat phase tooltip
		title_text = "Battle %d" % _entry.wave_number
		
		# variant name i.e. Boss, Normal TODO: localise!
		var variant_name: String = Phases.CombatVariant.keys()[_entry.subtype].capitalize()
		desc_text = "[color=#ff9999]%s[/color]" % variant_name
		
		# enemy preview
		# query the WaveEnemies class to see what spawns on this wave
		var enemies: Array[Array] = WaveEnemies.get_enemies_for_wave(_entry.wave_number)
		
		if enemies.is_empty():
			desc_text += "\nNo enemies incoming."
		else:
			desc_text += "\n[color=#cccccc]Incoming:[/color]"
			for stack: Array in enemies:
				# stack format is [Units.Type, Count]
				var type_id = stack[0]
				var count = stack[1]
				var unit_name = Units.Type.keys()[type_id].capitalize()
				desc_text += "\n• %dx %s" % [count, unit_name]
				
	else:
		# day phase tooltip
		title_text = "Peace %d" % _entry.wave_number
		
		# variant name
		var event_name: String = Phases.DayEvent.keys()[_entry.subtype].capitalize()
		desc_text = "[color=#55cc55]%s[/color]" % event_name
		
		# flavour text
		if _entry.subtype == Phases.DayEvent.EXPANSION:
			desc_text += "\nExpand your territory."
		elif _entry.subtype == Phases.DayEvent.REWARD_TOWER:
			desc_text += "\nChoose a new schematic."

	# instantiate tooltip
	_active_tooltip = KeywordService.TOOLTIP_PANEL.instantiate()
	add_child(_active_tooltip)
	
	_active_tooltip.show_tooltip({
		"title": title_text,
		"description": desc_text
	})

func _on_mouse_exited() -> void:
	if is_instance_valid(_active_tooltip):
		# We use the standard exit logic which handles grace periods/closing
		_active_tooltip.on_link_mouse_exited()
		_active_tooltip = null
