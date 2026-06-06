extends InteractiveRichTextLabel
class_name StatsLabel

var flux: float = 0.0
var used_capacity: float = 0.0
var total_capacity: float = 0.0
var health: float = 0.0

func _ready() -> void:
	super._ready()
	UI.update_flux.connect(_update_flux)
	UI.update_capacity.connect(_update_capacity)
	UI.update_health.connect(_update_health)

	UI.tutorial_manager.register_element(TutorialStep.Reference.PLAYER_STATS, self)

	if Run.has_active_run() and is_instance_valid(Run.player):
		_update_capacity(Run.player.used_capacity, Run.player.tower_capacity)
		_update_health(Run.player.hp)
		_update_flux(Run.player.flux)

func _update_flux(new_flux_value: float) -> void:
	flux = new_flux_value
	_update_label()

func _update_capacity(used: float, total: float) -> void:
	used_capacity = used
	total_capacity = total
	_update_label()

func _update_health(hp: float) -> void:
	health = hp
	_update_label()

func _update_label() -> void:
	var flux_text: String = "{GOLD}: %s" % str(floori(flux * 10) * 0.1)
	var capacity_text: String = "{POPULATION}: %s / %s" % [str(roundi(used_capacity * 10) * 0.1), str(roundi(total_capacity * 10) * 0.1)]
	var health_text: String = "{PLAYER_HP}: %s" % [str(roundi(health))]

	set_parsed_text(health_text + " " + flux_text + " " + capacity_text)
