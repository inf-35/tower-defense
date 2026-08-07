extends ClickyButton
class_name TowerOption

@export var card_motion: AnimatableUI
@export var card_panel: PanelContainer
@export var tower_icon: TextureRect
@export var tower_label: InteractiveRichTextLabel
@export var tower_meta: InteractiveRichTextLabel

const UNAFFORDABLE_ALPHA: float = 0.5
const UNAFFORDABLE_BRIGHTNESS: float = 0.8
const HOVER_Z_INDEX: int = 5
const DEFAULT_CARD_TINT: Color = Color(0.96, 0.936, 0.874, 1.0)
const RITE_CARD_TINT: Color = Color(0.93, 0.97, 1.0, 1.0)
const SELECTED_CARD_TINT: Color = Color(1.0, 0.893, 0.54, 1.0)*1.05
const ALLOW_TOWER_TYPE_REMOVAL: bool = false

var _hovered_upon: bool = false
var _tower_type: Towers.Type = Towers.Type.VOID
var _is_selected: bool = false
var _active_tooltip: TooltipPanel

func _ready() -> void: ##subscribes to hover and economy updates so the option can restyle itself without bespoke sidebar plumbing
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hovered_upon = true; _on_hover(_hovered_upon))
	mouse_exited.connect(func(): _hovered_upon = false; _on_hover(_hovered_upon))
	gui_input.connect(_on_gui_input)
	UI.update_flux.connect(func(_flux: float): _refresh_state())
	UI.update_capacity.connect(func(_used: float, _total: float): _refresh_state())

func display_tower_type(tower_type : Towers.Type) -> void: ##binds one authored tower type to this card and immediately refreshes its affordability state
	_tower_type = tower_type
	tower_icon.texture = Towers.get_tower_icon(tower_type)
	_refresh_card_tint()
	_refresh_state()

func set_selected(is_selected: bool) -> void: ##pins the active build option into a persistent highlighted card state without bypassing hover motion
	if _is_selected == is_selected:
		return
	_is_selected = is_selected
	if is_instance_valid(card_motion):
		card_motion.set_emphasized(_is_selected)
	_refresh_card_tint()

func _refresh_state() -> void: ##rebuilds the label so unavailable resource costs share the central bad color and blocked cards read clearly at a glance
	if _tower_type == Towers.Type.VOID:
		return

	var cost: float = Towers.get_tower_cost(_tower_type)
	var capacity_cost: float = Towers.get_tower_capacity(_tower_type)
	var has_gold: bool = Run.player.flux >= cost
	var has_capacity: bool = is_zero_approx(capacity_cost) or Run.player.has_capacity(_tower_type)
	var title_text: String = Towers.get_tower_name(_tower_type)
	if Towers.is_tower_rite(_tower_type):
		title_text += " (%s)" % Run.player.get_rite_count(_tower_type)

	var bad_color_hex: String = KeywordService.get_color_hex("bad")
	var gold_text: String = "{GOLD|icon_size=40%s} %s" % ["|color=%s" % bad_color_hex if not has_gold else "", str(cost)]
	if not has_gold:
		gold_text = KeywordService.wrap_text(gold_text, "bad")

	var capacity_text: String = "{POPULATION|icon_size=40%s} %s" % ["|color=%s" % bad_color_hex if not has_capacity else "", str(capacity_cost)]
	if not has_capacity:
		capacity_text = KeywordService.wrap_text(capacity_text, "bad")

	tower_label.set_parsed_text(title_text)
	tower_meta.set_parsed_text("%s    %s" % [gold_text, capacity_text])
	if has_gold and has_capacity:
		modulate = Color.WHITE
	else:
		modulate = Color(UNAFFORDABLE_BRIGHTNESS, UNAFFORDABLE_BRIGHTNESS, UNAFFORDABLE_BRIGHTNESS, UNAFFORDABLE_ALPHA)

func _on_hover(hover : bool) -> void: ##forwards root button hover into the shared card motion wrapper and lifts the hovered card above its neighbors
	z_index = HOVER_Z_INDEX if hover else 0
	if hover:
		_show_tower_tooltip()
	else:
		_hide_tower_tooltip()

	if not is_instance_valid(card_motion):
		return

	card_motion.set_hover_active(hover)

func _on_gui_input(event: InputEvent) -> void:
	if not ALLOW_TOWER_TYPE_REMOVAL:
		return
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	if _tower_type == Towers.Type.VOID:
		return
	if Towers.is_tower_rite(_tower_type):
		return
	if not Run.has_active_run() or not is_instance_valid(Run.player):
		return

	if Run.player.remove_tower_type(_tower_type):
		if is_instance_valid(ClickHandler.preview_tower_prototype) and ClickHandler.preview_tower_prototype.type == _tower_type:
			ClickHandler.select_entity(null)
		_hide_tower_tooltip(true)
		accept_event()

func _show_tower_tooltip() -> void:
	if _tower_type == Towers.Type.VOID:
		return
	if is_instance_valid(_active_tooltip):
		return

	var tooltip_data: Dictionary = _get_tower_tooltip_data()
	if tooltip_data.is_empty():
		return

	_active_tooltip = KeywordService.TOOLTIP_PANEL.instantiate() as TooltipPanel
	add_child(_active_tooltip)
	_active_tooltip.show_tooltip(tooltip_data)

func _hide_tower_tooltip(force_close: bool = false) -> void:
	if not is_instance_valid(_active_tooltip):
		_active_tooltip = null
		return

	if force_close:
		_active_tooltip.close()
	else:
		_active_tooltip.on_link_mouse_exited()
	_active_tooltip = null

func _get_tower_tooltip_data() -> Dictionary:
	var type_key: String = str(Towers.Type.keys()[_tower_type])
	var tooltip_data: Dictionary = KeywordService.get_keyword_data("T_%s" % type_key)
	if tooltip_data.is_empty():
		return tooltip_data
	if Towers.is_tower_rite(_tower_type):
		return tooltip_data
	if not ALLOW_TOWER_TYPE_REMOVAL:
		return tooltip_data

	tooltip_data = tooltip_data.duplicate(true)
	var prompt: String = KeywordService.wrap_text("RMB: destroy tower type", "bad")
	tooltip_data["description"] = "%s\n\n%s" % [str(tooltip_data.get("description", "")), prompt]
	return tooltip_data

func _refresh_card_tint() -> void: ##duplicates the shared local stylebox so each option can bias its card skin by tower family without affecting other card users
	if not is_instance_valid(card_panel):
		return

	var panel_style: StyleBox = card_panel.get_theme_stylebox(&"panel")
	if not panel_style is StyleBoxTexture:
		return

	var card_style: StyleBoxTexture = (panel_style as StyleBoxTexture).duplicate()
	if _is_selected:
		card_style.modulate_color = SELECTED_CARD_TINT
	else:
		card_style.modulate_color = RITE_CARD_TINT if Towers.is_tower_rite(_tower_type) else DEFAULT_CARD_TINT
	card_panel.add_theme_stylebox_override(&"panel", card_style)
