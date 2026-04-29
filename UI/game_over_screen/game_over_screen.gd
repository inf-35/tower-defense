extends Control
class_name GameOverScreen

@export var title_label: InteractiveRichTextLabel
@export var wave_label: InteractiveRichTextLabel
@export var relic_container: RelicDisplay
@export var tower_container: RelicDisplay
@export var restart_button: Button
@export var quit_button: Button
@export var debug_game_over_icons: bool = false

var _last_hovered_control_path: String = ""

const VICTORY_TITLE: String = "Victory!"
const VICTORY_COLOR: Color = Color("68bf8c") # Greenish
const DEFEAT_TITLE: String = "Defeat"
const DEFEAT_COLOR: Color = Color("bf6868") # Reddish

func _ready() -> void:
	# connect buttons
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	UI.display_game_over.connect(display)
	
	# ensure we start hidden if placed in the scene manually, 
	# though usually we instantiate this dynamically
	hide()

func _process(_delta: float) -> void:
	if not debug_game_over_icons or not visible:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hovered_path := "<none>"
	if is_instance_valid(hovered):
		hovered_path = str(hovered.get_path())
	if hovered_path != _last_hovered_control_path:
		_last_hovered_control_path = hovered_path
		_debug_log("viewport hovered control = %s" % hovered_path)

func _gui_input(event: InputEvent) -> void:
	if not debug_game_over_icons:
		return
	if event is InputEventMouseMotion:
		_debug_log("root gui_input motion")
	elif event is InputEventMouseButton:
		_debug_log("root gui_input button %d pressed=%s" % [event.button_index, str(event.pressed)])

func display(is_victory: bool) -> void:
	Clock.speed_multiplier = 0.0
	relic_container.debug_hover_icons = debug_game_over_icons
	tower_container.debug_hover_icons = debug_game_over_icons

	if is_victory:
		title_label.text = VICTORY_TITLE
		#title_label.modulate = VICTORY_COLOR
	else:
		title_label.text = DEFEAT_TITLE
		#title_label.modulate = DEFEAT_COLOR
		
	wave_label.text = "Reached Wave %d" % Phases.current_wave_number

	_populate_relics()
	_populate_towers()
	_debug_log("displayed end screen for wave %d" % Phases.current_wave_number)

	show()
	
	#animate entry
	modulate.a = 0.0
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)

func _populate_relics() -> void:
	relic_container.show_relics(Player.active_relics)
	_debug_log("populated %d relic icons" % Player.active_relics.size())

func _populate_towers() -> void:
	# to find "used" towers, we scan the island for unique active types
	# TODO: implement actual book-keeping
	var used_types: Dictionary[Towers.Type, bool] = {}
	
	# scan existing towers
	var all_towers = get_tree().get_nodes_in_group(References.TOWER_GROUP)
	for tower: Tower in all_towers:
		if not used_types.has(tower.type):
			used_types[tower.type] = true

	var sorted_types: Array[Towers.Type] = []
	for tower_type: Towers.Type in used_types:
		sorted_types.append(tower_type)
	sorted_types.sort()
	tower_container.show_towers(sorted_types)
	_debug_log("populated %d tower icons" % sorted_types.size())

func _on_restart_pressed() -> void:
	#delete the current save (which just died)
	SaveLoad.delete_save()
	# unpause before changing scenes or the new scene will start paused
	get_tree().paused = false
	# reload the main game scene
	get_tree().reload_current_scene.call_deferred()

func _on_quit_pressed() -> void:
	#delete the current save (which just died)
	SaveLoad.delete_save()
	get_tree().paused = false
	# return to main menu
	Phases.in_game = false
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")

func _debug_log(message: String) -> void:
	if debug_game_over_icons:
		print("[GameOverScreen] %s" % message)
