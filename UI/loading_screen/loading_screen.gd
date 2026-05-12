extends Control
class_name LoadingScreen

@export var status_label: Label
@export var progress_bar: ProgressBar

func _ready() -> void:
	UI.loading_screen = self
	visible = false

func show_loading(message: String, progress: float = -1.0) -> void:
	visible = true
	status_label.text = message
	if progress >= 0.0:
		progress_bar.value = progress * 100.0

func hide_loading() -> void:
	visible = false
