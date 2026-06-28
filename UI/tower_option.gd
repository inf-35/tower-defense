extends ClickyButton
class_name TowerOption

@export var card_motion: AnimatableUI
@export var card_panel: PanelContainer
@export var tower_icon: TextureRect
@export var tower_label: InteractiveRichTextLabel
@export var tower_meta: InteractiveRichTextLabel

const UNAFFORDABLE_ALPHA: float = 0.7
const HOVER_Z_INDEX: int = 5
const WARM_CARD_TINT: Color = Color(1.0, 0.9913333, 0.96, 1.0)
const RITE_CARD_TINT: Color = Color(0.93, 0.97, 1.0, 1.0)

var _hovered_upon: bool = false
var _tower_type: Towers.Type = Towers.Type.VOID

func _ready() -> void: ##subscribes to hover and economy updates so the option can restyle itself without bespoke sidebar plumbing
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hovered_upon = true; _on_hover(_hovered_upon))
	mouse_exited.connect(func(): _hovered_upon = false; _on_hover(_hovered_upon))
	UI.update_flux.connect(func(_flux: float): _refresh_state())
	UI.update_capacity.connect(func(_used: float, _total: float): _refresh_state())

func display_tower_type(tower_type : Towers.Type) -> void: ##binds one authored tower type to this card and immediately refreshes its affordability state
	_tower_type = tower_type
	tower_icon.texture = Towers.get_tower_icon(tower_type)
	_refresh_card_tint()
	_refresh_state()

func _refresh_state() -> void: ##rebuilds the label so unavailable resource costs share the central bad color and the whole card fades when blocked
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
	modulate.a = 1.0 if has_gold and has_capacity else UNAFFORDABLE_ALPHA

func _on_hover(hover : bool) -> void: ##forwards root button hover into the shared card motion wrapper and lifts the hovered card above its neighbors
	z_index = HOVER_Z_INDEX if hover else 0
	if not is_instance_valid(card_motion):
		return

	if hover and card_motion.has_method(&"_on_mouse_entered"):
		card_motion._on_mouse_entered()
	elif not hover and card_motion.has_method(&"_on_mouse_exited"):
		card_motion._on_mouse_exited()

func _refresh_card_tint() -> void: ##duplicates the shared local stylebox so each option can bias its card skin by tower family without affecting other card users
	if not is_instance_valid(card_panel):
		return

	var panel_style: StyleBox = card_panel.get_theme_stylebox(&"panel")
	if not panel_style is StyleBoxTexture:
		return

	var card_style: StyleBoxTexture = (panel_style as StyleBoxTexture).duplicate()
	card_style.modulate_color = RITE_CARD_TINT if Towers.is_tower_rite(_tower_type) else WARM_CARD_TINT
	card_panel.add_theme_stylebox_override(&"panel", card_style)
