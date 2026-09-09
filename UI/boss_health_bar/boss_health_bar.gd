extends PanelContainer
class_name BossHealthBar

@export var title_label: Label ##displays the active boss encounter name
@export var subwave_label: Label ##displays the one-based boss subwave index
@export var health_bar: ProgressBar ##top-screen health meter for the persistent boss
@export var health_label: Label ##numeric health readout paired with the boss meter

func _ready() -> void:
	visible = false
	UI.boss_encounter_started.connect(_on_boss_encounter_started)
	UI.boss_health_changed.connect(_on_boss_health_changed)
	UI.boss_subwave_changed.connect(_on_boss_subwave_changed)
	UI.boss_encounter_ended.connect(_on_boss_encounter_ended)

func _on_boss_encounter_started(title: String, boss_unit: Unit) -> void: ##shows the bar and seeds it from the boss unit if health is already ready
	visible = true
	title_label.text = title
	if is_instance_valid(boss_unit) and is_instance_valid(boss_unit.health_component):
		_on_boss_health_changed(boss_unit.health_component.max_health, boss_unit.health_component.health)

func _on_boss_health_changed(max_hp: float, hp: float) -> void: ##updates the boss meter from authoritative health-component values
	var safe_max_hp: float = maxf(max_hp, 1.0)
	health_bar.max_value = safe_max_hp
	health_bar.value = clampf(hp, 0.0, safe_max_hp)
	health_label.text = "%d / %d" % [ceili(hp), ceili(safe_max_hp)]

func _on_boss_subwave_changed(subwave_index: int) -> void: ##keeps prep and combat displays aligned to the next active subwave
	subwave_label.text = "Subwave %d" % subwave_index

func _on_boss_encounter_ended() -> void: ##hides stale boss presentation after final boss death
	visible = false
