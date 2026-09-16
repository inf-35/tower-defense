extends Node

signal fullscreen_changed(is_enabled: bool)

const DEFAULT_WINDOWED_SCREEN_SCALE: float = 0.6

var _windowed_size: Vector2i = Vector2i.ZERO
var _startup_settings_applied: bool = false

func _ready() -> void:
	pass

func is_fullscreen_enabled() -> bool:
	return _is_fullscreen_mode(get_window().mode)

func set_fullscreen_enabled(is_enabled: bool) -> void: ##applies the persistent fullscreen preference through the main window so scene changes do not own display state
	if OS.has_feature("web"):
		return

	var window: Window = get_window()
	var currently_fullscreen: bool = _is_fullscreen_mode(window.mode)
	if currently_fullscreen == is_enabled:
		return

	if is_enabled:
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		_windowed_size = _get_default_windowed_size()
		_restore_windowed_layout()
	_refresh_mouse_after_window_mode_change.call_deferred()

	fullscreen_changed.emit(is_enabled)

func apply_startup_settings(settings_data: Dictionary = {}) -> void: ##restores saved fullscreen state when present, otherwise applies one default centered windowed layout for desktop startup
	if OS.has_feature("web"):
		return
	if _startup_settings_applied:
		if settings_data.has("fullscreen_enabled"):
			load_profile_data(settings_data)
		return
	_startup_settings_applied = true
	if settings_data.has("fullscreen_enabled"):
		load_profile_data(settings_data)
		return
	_windowed_size = _get_default_windowed_size()
	_restore_windowed_layout()

func get_profile_data() -> Dictionary: ##serializes the window settings owned by this singleton into profile-safe data
	return {
		"fullscreen_enabled": is_fullscreen_enabled(),
	}

func load_profile_data(settings_data: Dictionary) -> void: ##hydrates window settings from persisted profile data without any scene-local window code
	set_fullscreen_enabled(bool(settings_data.get("fullscreen_enabled", false)))

func _restore_windowed_layout() -> void: ##restores the intended smaller windowed geometry after startup or leaving fullscreen
	var window: Window = get_window()
	if _windowed_size == Vector2i.ZERO:
		_windowed_size = _get_default_windowed_size()
	window.size = _windowed_size
	window.move_to_center()

func _get_default_windowed_size() -> Vector2i: ##derives the default desktop startup size from the current monitor instead of hardcoding a pixel size
	return Vector2i(Vector2(DisplayServer.screen_get_size()) * DEFAULT_WINDOWED_SCREEN_SCALE)

func _is_fullscreen_mode(mode: int) -> bool:
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN

func _refresh_mouse_after_window_mode_change() -> void:
	await get_tree().process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ClickHandler.refresh_custom_cursors()
