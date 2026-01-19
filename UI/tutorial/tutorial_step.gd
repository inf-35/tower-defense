extends Resource
class_name TutorialStep

enum TriggerType {
	WAIT_FOR_SIGNAL,    # Existing logic
	PRESS_ACTION,       # e.g. "Press Space"
	CAMERA_PAN,         # e.g. "Move camera 200 pixels"
	CAMERA_ZOOM,        # e.g. "Zoom in/out"
	HOVER_ELEMENT,
	BEGIN_TRIGGERED,
}

@export_multiline var instruction_text: String
@export_multiline var success_text: String ##text shown when condition is met.

@export var panel_anchor: TutorialManager.Anchor
@export var highlight_target: TutorialManager.Reference
@export var highlight: bool = true

@export_group("Completion Logic")
@export var trigger_type: TriggerType = TriggerType.WAIT_FOR_SIGNAL
@export var require_confirmation: bool = true ##after fulfilling requirements, do we still wait for confirmation

# For WAIT_FOR_SIGNAL: The signal name on UI bus
# For PRESS_ACTION: The Input Map action name (e.g. "camera_move_left", "ui_accept")
@export var trigger_signal: Signal
@export var desired_parameters: Array
@export var trigger_action: StringName ##corresponds to an input action
# For CAMERA_PAN: Distance in pixels
# For CAMERA_ZOOM: Ignored (any zoom counts)
@export var trigger_amount: float = 0.0
