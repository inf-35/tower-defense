extends ClickyButton
class_name EmbarkChoice

@export var motion: AnimatableUI ##visual child that expands without changing the button's layout footprint
@export var caption: Label ##label inside the animated paper face
@export var title: String = "" ##authored caption for simple environment, difficulty, and command buttons
@export var icon_target: TextureRect ##optional keep-aspect-centered icon with a scene-local selection outline and lock material
@export var paper_outline: Control ##optional silhouette drawn behind the paper face; selected choices or hovered commands reveal it
@export_range(0, 1000, 1) var required_wave_clear: int = 0 ##highest wave that must have been cleared in any run, zero leaves this choice available

var locked: bool = false ##derived from existing profile records whenever the embark page opens

func _ready() -> void:
	set_motion_target(motion)
	toggled.connect(_on_selection_changed)
	focus_entered.connect(motion.set_focus_active.bind(true))
	focus_exited.connect(motion.set_focus_active.bind(false))
	mouse_entered.connect(_refresh_outline)
	mouse_exited.connect(_refresh_outline)
	focus_entered.connect(_refresh_outline)
	focus_exited.connect(_refresh_outline)
	visibility_changed.connect(_on_visibility_changed)
	if icon_target != null:
		icon_target.resized.connect(_update_outline_draw_size)
		_update_outline_draw_size()
	refresh_unlock_state()
	_on_selection_changed(button_pressed)

func refresh_unlock_state() -> void: ##derives availability from existing saved clears without storing a parallel unlock flag
	locked = SaveLoad.profile.get_best_wave_clear() < required_wave_clear
	if required_wave_clear > 0:
		disabled = locked
		focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
	refresh_presentation()
	_refresh_outline()

func get_unlock_requirement() -> String: ##uses the same authored wave threshold for both availability and explanatory text
	if required_wave_clear == Phases.FINAL_WAVE:
		return "Complete a full run (wave %d) under any conditions to unlock." % required_wave_clear
	return "Complete wave %d under any conditions to unlock." % required_wave_clear

func refresh_presentation() -> void: ##redacts locked choices while retaining their authored titles and original texture alpha
	caption.text = "???" if locked else title
	if icon_target == null:
		return
	var icon_material: ShaderMaterial = icon_target.material as ShaderMaterial
	if icon_material != null:
		icon_material.set_shader_parameter(&"locked", locked)

func reset() -> void: ##clears selection and transient emphasis when the embark form is reopened
	set_pressed_no_signal(false)
	release_focus()
	motion.set_hover_active(false)
	motion.set_focus_active(false)
	_on_selection_changed(false)
	motion.snap_to_default()

func _on_selection_changed(is_selected: bool) -> void: ##keeps persistent scale and the optional icon outline on the same selection state
	motion.set_emphasized(is_selected and not locked)
	_refresh_outline()

func _refresh_outline() -> void: ##uses persistent selection for choices and hover or focus for non-toggle command buttons
	var is_outlined: bool = not locked and not disabled and is_visible_in_tree() and (button_pressed if toggle_mode else (is_hovered() or has_focus()))
	if paper_outline != null:
		paper_outline.visible = is_outlined
	if icon_target == null:
		return
	var outline_material: ShaderMaterial = icon_target.material as ShaderMaterial
	if outline_material != null:
		outline_material.set_shader_parameter(&"outline_enabled", is_outlined and paper_outline == null)

func _update_outline_draw_size() -> void: ##lets the shader expand only its drawing geometry while preserving the aspect-fitted image size
	var outline_material: ShaderMaterial = icon_target.material as ShaderMaterial
	if outline_material != null:
		outline_material.set_shader_parameter(&"draw_size", icon_target.size)

func _on_visibility_changed() -> void:
	_refresh_outline()
	if is_visible_in_tree():
		return
	motion.set_hover_active(false)
	motion.set_focus_active(false)
