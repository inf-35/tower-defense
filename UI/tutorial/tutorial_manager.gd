extends CanvasLayer
class_name TutorialManager

# --- Configuration ---
@export var overlay_color_rect: ColorRect
@export var instruction_label: InteractiveRichTextLabel
@export var advance_button: Button # Optional "Next" button for text-only steps

enum Reference { ##reference ids to control nodes
	NONE,
	TURRET_BUTTON,
	PALISADE_BUTTON,
	START_WAVE_BUTTON,
	WAVE_TIMELINE,
	TUTORIAL_TEXT,
}

# --- State ---
var _registered_ui_elements: Dictionary[Reference, Control] = {} # { "id": ControlNode }
var _current_step_index: int = -1
var _active_sequence: Array[TutorialStep] = []
var _target_node: Control = null # The currently highlighted node

var _monitor_start_val: Vector2 = Vector2.ZERO # Stores initial camera pos/zoom
var _monitoring_active: bool = false ##are we currently monitoring for a camera pos/zoom threshold

# --- Internal ---
var _shader_mat: ShaderMaterial

func _ready() -> void:
	# Setup Overlay
	_shader_mat = overlay_color_rect.material as ShaderMaterial
	overlay_color_rect.visible = false
	instruction_label.visible = false
	
	_shader_mat.set_shader_parameter(&"is_active", false)

	# Input Handling on the overlay rect itself
	# use gui_input to intercept clicks
	overlay_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_color_rect.gui_input.connect(_process_overlay_input)
	# Register self to UI singleton so other scripts can find us
	UI.tutorial_manager = self
	register_element(Reference.TUTORIAL_TEXT, instruction_label)

func _process(_delta: float) -> void:
	# Dynamic Tracking: If the UI element moves (e.g. animatable UI), follow it
	if visible and is_instance_valid(_target_node):
		_update_spotlight_position(_target_node)
		
	if not _monitoring_active or _current_step_index == -1:
		return
		
	_check_step_completion()

func _process_overlay_input(input_event: InputEvent):
	print(input_event)

# --- Public API: Registration ---
# UI elements call this in their _ready(): 
# UI.tutorial_manager.register_element("build_cannon_btn", self)
func register_element(id: Reference, node: Control) -> void:
	_registered_ui_elements[id] = node

# --- Public API: Sequences ---
func start_sequence(steps: Array[TutorialStep]) -> void:
	_active_sequence = steps
	_current_step_index = -1
	visible = true
	overlay_color_rect.visible = true
	instruction_label.visible = true
	_advance_step()

func end_tutorial() -> void:
	visible = false
	instruction_label.visible = false
	overlay_color_rect.visible = false
	_current_step_index = -1
	_target_node = null
	# reset shader
	_shader_mat.set_shader_parameter("is_active", false)

func _advance_step() -> void:
	_current_step_index += 1
	if _current_step_index >= _active_sequence.size():
		end_tutorial()
		return
		
	var step := _active_sequence[_current_step_index]
	if step.highlight_target != Reference.NONE:
		_target_node = _registered_ui_elements[step.highlight_target]
		_shader_mat.set_shader_parameter(&"is_active", true)
	else:
		_shader_mat.set_shader_parameter(&"is_active", false)
	instruction_label.text = step.instruction_text

	_monitoring_active = true
	var cam := References.camera
	
	match step.trigger_type:
		TutorialStep.TriggerType.WAIT_FOR_SIGNAL:
			# ... (Existing Signal Logic) ...
			if step.trigger_signal:
				step.trigger_signal.connect(_on_trigger_signal)
				
		TutorialStep.TriggerType.CAMERA_PAN:
			if is_instance_valid(cam):
				_monitor_start_val = cam.global_position
		
		TutorialStep.TriggerType.CAMERA_ZOOM:
			if is_instance_valid(cam):
				_monitor_start_val = cam.zoom
			
		TutorialStep.TriggerType.PRESS_ACTION:
			pass

func _check_step_completion() -> void:
	var step = _active_sequence[_current_step_index]
	var cam = References.camera
	if not is_instance_valid(cam): return

	match step.trigger_type:
		TutorialStep.TriggerType.CAMERA_PAN:
			# Check distance moved
			var dist: float = _monitor_start_val.distance_to(cam.global_position)
			if dist >= step.trigger_amount:
				_complete_step()
				
		TutorialStep.TriggerType.CAMERA_ZOOM:
			# Check deviation from start zoom
			var diff = (_monitor_start_val - cam.zoom).length()
			if diff > step.trigger_amount: # Threshold to prevent micro-jitter triggering it
				_complete_step()
				
		TutorialStep.TriggerType.HOVER_ELEMENT:
			# We rely on _target_node, which is set based on step.highlight_target_id
			if is_instance_valid(_target_node) and _target_node.visible:
				var mouse_pos = _target_node.get_global_mouse_position()
				var rect = _target_node.get_global_rect()
				# Check if mouse is inside the element's bounds
				if rect.has_point(mouse_pos):
					if rect.has_point(get_viewport().get_mouse_position()):
						_complete_step()
	
func _complete_step() -> void:
	if not _monitoring_active: return # Prevent double triggers
	_monitoring_active = false
	
	var step := _active_sequence[_current_step_index]
	if step.trigger_signal and step.trigger_signal.is_connected(_on_trigger_signal):
		step.trigger_signal.disconnect(_on_trigger_signal)
	
	await get_tree().create_timer(0.2).timeout
	print("Completed step!")
	_advance_step()

func _update_spotlight_position(node: Control) -> void:
	# Convert node rect to Screen UV coordinates for the shader
	var viewport_size = get_viewport().get_visible_rect().size
	var rect = node.get_global_rect()
	
	var center = rect.get_center()
	var uv_center = center / viewport_size
	var uv_size = rect.size / viewport_size
	_shader_mat.set_shader_parameter(&"spotlight_center", uv_center)
	_shader_mat.set_shader_parameter(&"spotlight_size", uv_size)

func _on_trigger_signal(...args) -> void:
	# generic handler that accepts many arguments to be compatible with any signal signature
	var desired_parameters: Array = _active_sequence[_current_step_index].desired_parameters
	var valid: bool = true
	for i: int in len(desired_parameters):
		if (not args.has(i)) or desired_parameters[i] != args[i]:
			valid = false
			break
			
	if valid:
		_complete_step()
