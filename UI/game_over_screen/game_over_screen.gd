extends Control
class_name GameOverScreen

@export var title_label: InteractiveRichTextLabel
@export var wave_label: InteractiveRichTextLabel
@export var relic_container: GridContainer
@export var tower_container: GridContainer
@export var restart_button: Button
@export var quit_button: Button

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

func display(is_victory: bool) -> void:
	Clock.speed_multiplier = 0.0

	if is_victory:
		title_label.text = VICTORY_TITLE
		#title_label.modulate = VICTORY_COLOR
	else:
		title_label.text = DEFEAT_TITLE
		#title_label.modulate = DEFEAT_COLOR
		
	wave_label.text = "Reached Wave %d" % Phases.current_wave_number

	_populate_relics()
	_populate_towers()

	show()
	
	#animate entry
	modulate.a = 0.0
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)

func _populate_relics() -> void:
	# clear placeholders
	for child in relic_container.get_children():
		child.queue_free()
		
	# iterate player relics
	for relic: RelicData in Player.active_relics:
		var icon := TextureRect.new()
		icon.texture = relic.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		icon.tooltip_text = relic.title
		relic_container.add_child(icon)

func _populate_towers() -> void:
	for child in tower_container.get_children():
		child.queue_free()
		
	# to find "used" towers, we scan the island for unique active types
	# TODO: implement actual book-keeping
	var used_types: Dictionary[Towers.Type, bool] = {}
	
	# scan existing towers
	var all_towers = get_tree().get_nodes_in_group(References.TOWER_GROUP)
	for tower: Tower in all_towers:
		if not used_types.has(tower.type):
			used_types[tower.type] = true
			
	# instantiate icons
	for type: Towers.Type in used_types:
		var icon := TextureRect.new()
		icon.texture = Towers.get_tower_icon(type)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		icon.tooltip_text = Towers.get_tower_name(type)
		tower_container.add_child(icon)

func _on_restart_pressed() -> void:
	# unpause before changing scenes or the new scene will start paused
	get_tree().paused = false
	# reload the main game scene
	# TODO: ensure _ready of phases actually resets things
	get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	get_tree().paused = false
	# return to main menu
	get_tree().change_scene_to_file("res://main_menu.tscn")
