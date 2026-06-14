extends CanvasLayer
class_name TutorialManager

signal start_wave_lock_changed(locked: bool)

#--- configuration ---
@export var overlay_color_rect: ColorRect
@export var instruction_panel: TutorialPanel
@export var advance_button: Button #optional "next" button for text-only steps

@export var central_anchor: Control
@export var tower_bar_anchor: Control
@export var player_stats_anchor: Control
@export var timeline_anchor: Control
@export var start_wave_anchor: Control

#--- state ---
var _registered_ui_elements: Dictionary[TutorialStep.Reference, Control] = {} #{ "id": controlnode }
var _current_step_index: int = -1
var _active_sequence: Array[TutorialStep] = []
var _target_node: Control = null #the currently highlighted node
var _highlight_target: bool = true
var _waiting_for_confirmation: bool = false

var _monitor_start_val: Vector2 = Vector2.ZERO #stores initial camera pos/zoom
var _monitoring_active: bool = false ##are we currently monitoring for a camera pos/zoom threshold

var _anchor_node: Control

var _current_tutorial_type: Player.TutorialFlag
var _world_hint_open: bool = false
var _world_hint_target: Tower
var _world_hint_previous_speed: float = Clock.BASE_SPEED
var _default_instruction_label_min_size: Vector2
var _start_wave_locked: bool = false

#--- internal ---
var _shader_mat: ShaderMaterial

func _ready() -> void:
	#setup overlay
	_shader_mat = overlay_color_rect.material as ShaderMaterial
	overlay_color_rect.visible = false
	instruction_panel.visible = false

	_shader_mat.set_shader_parameter(&"is_active", false)

	#input handling on the overlay rect itself
	#use gui_input to intercept clicks
	overlay_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_color_rect.gui_input.connect(_process_overlay_input)
	#register self to ui singleton so other scripts can find us
	UI.tutorial_manager = self
	register_element(TutorialStep.Reference.TUTORIAL_TEXT, instruction_panel)
	_default_instruction_label_min_size = instruction_panel.label.custom_minimum_size

func _process(_delta: float) -> void:
	if visible and is_instance_valid(_target_node) and _highlight_target:
		_update_spotlight_position(_target_node)

	if is_instance_valid(instruction_panel) and instruction_panel.visible:
		if _has_active_world_target():
			_update_world_hint_panel()
		elif is_instance_valid(_anchor_node):
			instruction_panel.position = _anchor_node.position
			instruction_panel.size = _anchor_node.size

	if not _monitoring_active or _current_step_index == -1:
		return

	_check_step_completion()

func _input(event: InputEvent) -> void:
	#new: handle q confirmation
	if _waiting_for_confirmation:
		if event.is_action_pressed("interact"): #map 'q' to this action
			_advance_step()

func _process_overlay_input(input_event: InputEvent) -> void:
	print(input_event)

func _has_active_sequence() -> bool:
	return _current_step_index != -1

func _has_active_world_target() -> bool:
	if not _has_active_sequence():
		return false
	if not is_instance_valid(_world_hint_target):
		return false
	if _current_step_index < 0 or _current_step_index >= _active_sequence.size():
		return false
	return _active_sequence[_current_step_index].panel_anchor == TutorialStep.Anchor.TARGET_OFFSET

func is_start_wave_locked() -> bool:
	return _start_wave_locked

func _is_world_hint_active() -> bool:
	return _has_active_world_target()

func _hide_world_hint() -> void:
	if _world_hint_open:
		Clock.speed_multiplier = _world_hint_previous_speed
	_world_hint_open = false
	_world_hint_target = null
	_waiting_for_confirmation = false
	instruction_panel.label.custom_minimum_size = _default_instruction_label_min_size
	if not _has_active_sequence():
		instruction_panel.visible = false

func _dismiss_world_hint() -> void:
	_hide_world_hint()
	overlay_color_rect.visible = false
	_shader_mat.set_shader_parameter(&"is_active", false)

func _update_world_hint_panel() -> void:
	if not is_instance_valid(_world_hint_target):
		_hide_world_hint()
		return

	var step: TutorialStep = _active_sequence[_current_step_index]
	var screen_pos := _world_hint_target.get_global_transform_with_canvas().origin
	screen_pos.x += float(_world_hint_target.size.x) * Island.CELL_SIZE * 0.35
	screen_pos.y -= float(_world_hint_target.size.y) * Island.CELL_SIZE * 0.45

	instruction_panel.reset_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_pos : Vector2 = screen_pos + step.target_offset
	panel_pos.x = clampf(panel_pos.x, 12.0, viewport_size.x - instruction_panel.size.x - 12.0)
	panel_pos.y = clampf(panel_pos.y, 12.0, viewport_size.y - instruction_panel.size.y - 12.0)
	instruction_panel.position = panel_pos

#--- public api: registration ---
#ui elements call this in their _ready():
#ui.tutorial_manager.register_element("build_cannon_btn", self)
func register_element(id: TutorialStep.Reference, node: Control) -> void:
	_registered_ui_elements[id] = node

#--- public api: sequences ---
func start_sequence(steps: Array[TutorialStep], tutorial_type: Player.TutorialFlag) -> void:
	_hide_world_hint()
	#reject tutorials already completed
	if Run.player.completed_tutorials[tutorial_type]:
		return
	_active_sequence = steps
	_current_step_index = -1
	visible = true
	overlay_color_rect.visible = true
	instruction_panel.visible = true
	_current_tutorial_type = tutorial_type
	_advance_step()

func start_world_sequence(steps: Array[TutorialStep], tutorial_type: Player.TutorialFlag, tower: Tower) -> void: ##starts a normal tutorial resource sequence, but anchors its panel beside a world tower target instead of a ui control
	if not is_instance_valid(tower):
		return
	if Run.player.completed_tutorials[tutorial_type]:
		return

	_hide_world_hint()
	_world_hint_target = tower
	_active_sequence = steps
	_current_step_index = -1
	visible = true
	overlay_color_rect.visible = true
	instruction_panel.visible = true
	_current_tutorial_type = tutorial_type
	_advance_step()

func end_tutorial() -> void:
	_hide_world_hint()
	visible = false
	instruction_panel.visible = false
	overlay_color_rect.visible = false
	_current_step_index = -1
	_target_node = null
	Run.player.completed_tutorials[_current_tutorial_type] = true
	#reset shader
	_shader_mat.set_shader_parameter("is_active", false)

func _advance_step() -> void: ##activates the next authored step, applying any lock state and tutorial text styling before monitoring completion
	Audio.play_sound(ID.Sounds.BUTTON_CLICK_SOUND)
	_waiting_for_confirmation = false
	_current_step_index += 1
	if _current_step_index >= _active_sequence.size():
		end_tutorial()
		return

	var step := _active_sequence[_current_step_index]
	if step.pause_clock and not _world_hint_open:
		_world_hint_open = true
		_world_hint_previous_speed = Clock.speed_multiplier
		Clock.speed_multiplier = Clock.PAUSE_SPEED
	elif not step.pause_clock and _world_hint_open:
		_hide_world_hint()

	if step.override_start_wave_lock:
		_set_start_wave_locked(step.start_wave_locked)
	if step.highlight_target != TutorialStep.Reference.NONE:
		_target_node = _registered_ui_elements[step.highlight_target]
	else:
		_target_node = null

	if step.highlight_target != TutorialStep.Reference.NONE and step.highlight:
		_shader_mat.set_shader_parameter(&"is_active", true)
	else:
		_shader_mat.set_shader_parameter(&"is_active", false)
	instruction_panel.label.set_parsed_text(KeywordService.style_tutorial_text(step.instruction_text))

	_monitoring_active = true
	var cam := Run.references.camera

	match step.trigger_type:
		TutorialStep.TriggerType.WAIT_FOR_SIGNAL:
			#... (existing signal logic) ...
			if step.trigger_signal:
				print(step.trigger_signal)
				step.trigger_signal.connect(_on_trigger_signal)

		TutorialStep.TriggerType.CAMERA_PAN:
			if is_instance_valid(cam):
				_monitor_start_val = cam.global_position

		TutorialStep.TriggerType.CAMERA_ZOOM:
			if is_instance_valid(cam):
				_monitor_start_val = cam.zoom

		TutorialStep.TriggerType.PRESS_ACTION:
			pass

	match step.panel_anchor:
		TutorialStep.Anchor.CENTRAL_ANCHOR:
			_anchor_node = central_anchor
		TutorialStep.Anchor.TOWER_BAR_ANCHOR:
			_anchor_node = tower_bar_anchor
		TutorialStep.Anchor.PLAYER_STATS_ANCHOR:
			_anchor_node = player_stats_anchor
		TutorialStep.Anchor.TIMELINE_ANCHOR:
			_anchor_node = timeline_anchor
		TutorialStep.Anchor.START_WAVE_ANCHOR:
			_anchor_node = start_wave_anchor
		TutorialStep.Anchor.TARGET_OFFSET:
			_anchor_node = null


func _check_step_completion() -> void:
	var step = _active_sequence[_current_step_index]
	var cam = Run.references.camera
	if not is_instance_valid(cam): return

	match step.trigger_type:
		TutorialStep.TriggerType.BEGIN_TRIGGERED:
			_complete_step()

		TutorialStep.TriggerType.CAMERA_PAN:
			#check distance moved
			var dist: float = _monitor_start_val.distance_to(cam.global_position)
			if dist >= step.trigger_amount:
				_complete_step()

		TutorialStep.TriggerType.CAMERA_ZOOM:
			#check deviation from start zoom
			var diff = (_monitor_start_val - cam.zoom).length()
			if diff > step.trigger_amount: #threshold to prevent micro-jitter triggering it
				_complete_step()

		TutorialStep.TriggerType.HOVER_ELEMENT:
			#we rely on _target_node, which is set based on step.highlight_target_id
			if is_instance_valid(_target_node) and _target_node.visible:
				var mouse_pos = _target_node.get_global_mouse_position()
				var rect = _target_node.get_global_rect()
				#check if mouse is inside the element's bounds
				if rect.has_point(mouse_pos):
					if rect.has_point(get_viewport().get_mouse_position()):
						_complete_step()

func _complete_step() -> void:
	if not _monitoring_active: return #prevent double triggers
	_monitoring_active = false

	var step := _active_sequence[_current_step_index]
	if step.trigger_signal and step.trigger_signal.is_connected(_on_trigger_signal):
		step.trigger_signal.disconnect(_on_trigger_signal)

	if step.require_confirmation:
		Audio.play_sound(ID.Sounds.BUTTON_HOVER_SOUND)
		_waiting_for_confirmation = true
		instruction_panel.label.set_parsed_text(KeywordService.style_tutorial_text(step.success_text))
	else:
		_advance_step()

func _update_spotlight_position(node: Control) -> void:
	#convert node rect to screen uv coordinates for the shader
	var viewport_size = get_viewport().get_visible_rect().size
	var rect = node.get_global_rect()

	var center = rect.get_center()
	var uv_center = center / viewport_size
	var uv_size = rect.size / viewport_size
	_shader_mat.set_shader_parameter(&"spotlight_center", uv_center)
	_shader_mat.set_shader_parameter(&"spotlight_size", uv_size)

func _on_trigger_signal(...args) -> void:
	print("signal: ", args)
	#generic handler that accepts many arguments to be compatible with any signal signature
	var desired_parameters: Array = _active_sequence[_current_step_index].desired_parameters
	print(args, " / ", desired_parameters)
	var valid: bool = true
	for i: int in range(desired_parameters.size()):
		if i >= args.size() or desired_parameters[i] != args[i]:
			valid = false
			break

	if valid:
		_complete_step()

func _set_start_wave_locked(locked: bool) -> void:
	if _start_wave_locked == locked:
		return
	_start_wave_locked = locked
	start_wave_lock_changed.emit(locked)
