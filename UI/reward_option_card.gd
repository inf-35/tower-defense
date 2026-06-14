extends Control
class_name RewardOptionCard

signal selected()
signal hovered()
signal unhovered()

#--- references to animatable wrappers ---
#these are the nodes with the 'animatableui.gd' script attached
@export var _icon_target: Control
@export var _panel_target: Control

#--- references to content ---
#these are the actual visual containers (children of the wrappers)
@export var _real_icon_panel: Control
@export var _real_description_panel: Control

@export var icon: TextureRect
@export var title: InteractiveRichTextLabel
@export var tower_meta: InteractiveRichTextLabel
@export var description: InteractiveRichTextLabel

var _reward_data: Reward

func _ready() -> void:
	#ensure the container itself can catch mouse events
	mouse_filter = Control.MOUSE_FILTER_STOP

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

#public setup function
func setup(reward: Reward, index: int) -> void:
	_reward_data = reward

	#apply data
	_apply_visuals(reward)

	#configure animation stagger
	#access the animatableui script properties on the targets
	var delay_base = index * 0.1

	if is_instance_valid(_icon_target) and "entrance_delay" in _icon_target:
		_icon_target.entrance_delay = delay_base
		_icon_target.auto_play_entrance = true
		_icon_target.animate_entrance()

	if is_instance_valid(_panel_target) and "entrance_delay" in _panel_target:
		_panel_target.entrance_delay = delay_base + 0.05 #slight offset for fluid feel
		_panel_target.auto_play_entrance = true
		_panel_target.animate_entrance()

func _apply_visuals(reward: Reward) -> void:
	var title_text: String = "Unknown Reward"
	var desc_text: String = reward.description
	var icon_tex: Texture2D = null

	match reward.type:
		Reward.Type.UNLOCK_TOWER:
			var type: Towers.Type = reward.tower_type
			#fetch tower preview/icon
			icon_tex = Towers.get_tower_icon(type)
			title_text = "New Tower: [color=#ffcc66]%s[/color]" % Towers.get_tower_name(type)
			desc_text = _build_tower_card_description(type)

		Reward.Type.ADD_RELIC:
			var relic: RelicData = reward.relic
			icon_tex = relic.icon
			title_text = "New Relic: [color=#66ccff]%s[/color]" % relic.title
			desc_text = relic.description

		Reward.Type.ADD_RITE:
			var type: Towers.Type = reward.rite_type
			#fetch tower preview/icon
			icon_tex = Towers.get_tower_icon(type)
			title_text = "New Tower: [color=#ffcc66]%s[/color]" % Towers.get_tower_name(type)
			desc_text = _build_tower_card_description(type)

		Reward.Type.ADD_FLUX:
			var amount: float = reward.flux_amount
			var gold_data: Dictionary = KeywordService.get_keyword_data("GOLD")
			icon_tex = gold_data.get("icon", null)
			title_text = reward.title if reward.title != "" else "Gold Cache"
			desc_text = reward.description if reward.description != "" else "Gain %.0f {GOLD} immediately." % amount

	if icon:
		icon.texture = icon_tex

	if title:
		title.set_parsed_text(title_text)

	if tower_meta:
		tower_meta.visible = false
		tower_meta.set_parsed_text("")

	if description:
		description.set_parsed_text(desc_text)

func _get_tower_meta_text(tower_type: Towers.Type) -> String:
	var size: Vector2i = Towers.get_tower_size(tower_type)
	return "{GOLD} %.2f    {SIZE} %dx%d" % [
		Towers.get_tower_base_cost(tower_type),
		size.x,
		size.y,
	]

func _build_tower_card_description(tower_type: Towers.Type) -> String:
	return "%s\n%s" % [
		_get_tower_meta_text(tower_type),
		KeywordService.resolve_tower_description_from_type(tower_type),
	]

#--- input handling ---

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			Audio.play_sound(ID.Sounds.BUTTON_CLICK_SOUND, -1.0)
			selected.emit()

#manually trigger the hover animations on the children wrappers
func _on_mouse_entered() -> void:
	Audio.play_sound(ID.Sounds.BUTTON_HOVER_SOUND, -5.0)
	hovered.emit()
	if is_instance_valid(_icon_target) and _icon_target.has_method("_on_mouse_entered"):
		_icon_target._on_mouse_entered()
	if is_instance_valid(_panel_target) and _panel_target.has_method("_on_mouse_entered"):
		_panel_target._on_mouse_entered()

func _on_mouse_exited() -> void:
	unhovered.emit()
	if is_instance_valid(_icon_target) and _icon_target.has_method("_on_mouse_exited"):
		_icon_target._on_mouse_exited()
	if is_instance_valid(_panel_target) and _panel_target.has_method("_on_mouse_exited"):
		_panel_target._on_mouse_exited()
