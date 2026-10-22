extends ClickyButton
class_name EmbarkChoice

@export var motion: AnimatableUI ##visual child that expands without changing the button's layout footprint
@export var caption: Label ##label inside the animated paper face
@export var title: String = "" ##authored caption for simple environment, difficulty, and command buttons

func _ready() -> void:
	set_motion_target(motion)
	caption.text = title
	toggled.connect(motion.set_emphasized)
	focus_entered.connect(motion.set_focus_active.bind(true))
	focus_exited.connect(motion.set_focus_active.bind(false))
	visibility_changed.connect(_on_visibility_changed)

func reset() -> void: ##clears selection and transient emphasis when the embark form is reopened
	set_pressed_no_signal(false)
	release_focus()
	motion.set_hover_active(false)
	motion.set_focus_active(false)
	motion.set_emphasized(false)
	motion.snap_to_default()

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		return
	motion.set_hover_active(false)
	motion.set_focus_active(false)
