extends Control
class_name DamageTrackerRow

signal pressed(entry_id: String)

@export var tower_icon: TextureRect
@export var tower_name_label: Label
@export var damage_bar: ProgressBar
@export var damage_value_label: Label

var _entry_id: String = ""
var _is_focusable: bool = false

func _gui_input(event: InputEvent) -> void:
	if not _is_focusable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		pressed.emit(_entry_id)
		get_viewport().set_input_as_handled()

func display_entry(entry: Dictionary, max_damage: float) -> void: ##binds one ranking entry and updates its normalized bar state
	_entry_id = str(entry.get("entry_id", ""))
	_is_focusable = bool(entry.get("is_focusable", false))
	tower_icon.texture = _resolve_icon(entry)
	tower_name_label.text = str(entry["tower_name"])
	damage_bar.max_value = maxf(max_damage, 0.001)
	damage_bar.value = float(entry["damage_total"])
	damage_value_label.text = _format_damage(float(entry["damage_total"]))
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _is_focusable else Control.CURSOR_ARROW

func _resolve_icon(entry: Dictionary) -> Texture2D:
	var tower_type: int = int(entry.get("tower_type", Towers.Type.VOID))
	if tower_type != Towers.Type.VOID:
		return Towers.get_tower_icon(tower_type)

	var status_type: int = int(entry.get("status_type", -1))
	if status_type < 0:
		return null

	var keyword_data: Dictionary = KeywordService.get_keyword_data(Attributes.Status.keys()[status_type])
	return keyword_data.get("icon", null) as Texture2D

func _format_damage(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.1))
