extends Node

@export var canvas_layers: Array[CanvasLayer] = [] ##hud and tooltip canvases hidden together without altering child panel states
@export var canvas_items: Array[CanvasItem] = [] ##world-space overlays included in the same presentation toggle

var _hidden: bool = false
var _layer_visibility: Array[bool] = []
var _item_visibility: Array[bool] = []

func _unhandled_key_input(event: InputEvent) -> void: ##toggles presentation after focused controls have had a chance to consume keyboard input
	if not event.is_action_pressed(&"toggle_ui", false, true):
		return
	_toggle_visibility()
	get_viewport().set_input_as_handled()

func _toggle_visibility() -> void: ##restores each root's previous visibility while leaving ongoing child ui updates intact
	if not _hidden:
		_layer_visibility.clear()
		_item_visibility.clear()
		for layer: CanvasLayer in canvas_layers:
			_layer_visibility.append(layer.visible)
			layer.visible = false
		for item: CanvasItem in canvas_items:
			_item_visibility.append(item.visible)
			item.visible = false
	else:
		for index: int in canvas_layers.size():
			canvas_layers[index].visible = _layer_visibility[index]
		for index: int in canvas_items.size():
			canvas_items[index].visible = _item_visibility[index]
	_hidden = not _hidden
