# SidebarUI.gd
extends Control
class_name SidebarUI

signal tower_selected(type_id: int)

@onready var _vbox: VBoxContainer = $Panel/VBoxContainer

func _ready() -> void:
	_populate_buttons()

func _populate_buttons() -> void:
	for child in _vbox.get_children():
		child.free()

	for type_id: Towers.Type in Towers.Type.values():
		var btn := Button.new()
		btn.text = str(type_id).pad_zeros(2) + ": " + Towers.get_tower_scene(type_id).resource_name
		btn.name = "Btn_%s" % Towers.get_tower_scene(type_id).resource_name
		btn.pressed.connect(_on_button_pressed.bind(type_id))
		_vbox.add_child(btn)

func _on_button_pressed(type_id: int) -> void:
	emit_signal("tower_selected", type_id)
	ClickHandler.tower_type = type_id
