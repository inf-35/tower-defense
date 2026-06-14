extends ClickyButton
class_name TowerOption

@export var tower_icon: TextureRect
@export var tower_label: InteractiveRichTextLabel

const UNAFFORDABLE_ALPHA: float = 0.7

var _hovered_upon: bool = false
var _tower_type: Towers.Type = Towers.Type.VOID

func _ready() -> void: ##subscribes to hover and economy updates so the option can restyle itself without bespoke sidebar plumbing
	mouse_entered.connect(func(): _hovered_upon = true; _on_hover(_hovered_upon))
	mouse_exited.connect(func(): _hovered_upon = false; _on_hover(_hovered_upon))
	UI.update_flux.connect(func(_flux: float): _refresh_state())
	UI.update_capacity.connect(func(_used: float, _total: float): _refresh_state())

func display_tower_type(tower_type : Towers.Type) -> void: ##binds one authored tower type to this card and immediately refreshes its affordability state
	_tower_type = tower_type
	tower_icon.texture = Towers.get_tower_icon(tower_type)
	_refresh_state()

func _refresh_state() -> void: ##rebuilds the label so unavailable resource costs share the central bad color and the whole card fades when blocked
	if _tower_type == Towers.Type.VOID:
		return

	var cost: float = Towers.get_tower_cost(_tower_type)
	var capacity_cost: float = Towers.get_tower_capacity(_tower_type)
	var has_gold: bool = Run.player.flux >= cost
	var has_capacity: bool = is_zero_approx(capacity_cost) or Run.player.has_capacity(_tower_type)
	var text: String = ""
	text = Towers.get_tower_name(_tower_type)
	if Towers.is_tower_rite(_tower_type):
		text += " (%s)" % Run.player.get_rite_count(_tower_type)

	var bad_color_hex: String = KeywordService.get_bad_color_hex()
	var gold_text: String = "{GOLD|icon_size=40%s} %s" % ["|color=%s" % bad_color_hex if not has_gold else "", str(cost)]
	if not has_gold:
		gold_text = KeywordService.wrap_bad_text(gold_text)

	var capacity_text: String = "{POPULATION|icon_size=40%s} %s" % ["|color=%s" % bad_color_hex if not has_capacity else "", str(capacity_cost)]
	if not has_capacity:
		capacity_text = KeywordService.wrap_bad_text(capacity_text)

	text += "\n%s %s" % [gold_text, capacity_text]
	tower_label.set_parsed_text(text)
	modulate.a = 1.0 if has_gold and has_capacity else UNAFFORDABLE_ALPHA

func _on_hover(_hover : bool) -> void:
	pass
