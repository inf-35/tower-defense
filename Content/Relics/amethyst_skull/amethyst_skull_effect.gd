extends EffectPrototype
class_name AmethystSkullEffect

#--- configuration ---
@export var search_radius: float = 200.0
@export var required_status: Attributes.Status = Attributes.Status.CURSED
@export var damage_multiplier: float = 0.0
@export var projectile_data: AttackData ##defines the spirit/bolt visual and speed
@export var delay: float = 0.2 ##delay in seconds between death and hit.

func _init() -> void:
	#trigger when a unit dies
	event_hooks = [GameEvent.EventType.DIED]
	global = true

#--- instance factory ---
func create_instance() -> EffectInstance:
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

#--- logic handlers ---

func _handle_attach(_instance: EffectInstance) -> void:
	pass

func _handle_detach(_instance: EffectInstance) -> void:
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void:
	if event.event_type != GameEvent.EventType.DIED:
		return

	var dead_unit: Unit = event.unit
	if not is_instance_valid(dead_unit) or not dead_unit.hostile:
		return

	var hit_report: HitReportData = event.data as HitReportData
	var killer: Unit = hit_report.source

	#1. check condition: was the dead unit cursed?
	if not is_instance_valid(dead_unit.modifiers_component):
		return
	if not dead_unit.modifiers_component.has_status(required_status):
		return

	if projectile_data == null:
		push_warning("RestlessSpiritsEffect: Triggered but no AttackData assigned.")
		return

	var target = _find_cursed_target(dead_unit)

	if target:
		_attack(instance, hit_report, dead_unit, target, killer)

func _find_cursed_target(origin_unit: Unit) -> Unit:
	#get all enemies in range
	#exclude the dead unit itself
	var candidates: Array[Unit] = CombatManager.get_units_in_radius(
		search_radius,
		origin_unit.global_position,
		origin_unit.hostile,
		[origin_unit]
	)

	#filter for cursed ones
	var valid_targets: Array[Unit] = []
	for candidate in candidates:
		if is_instance_valid(candidate.modifiers_component) and candidate.modifiers_component.has_status(required_status):
			valid_targets.append(candidate)

	if valid_targets.is_empty():
		return null

	#pick random or closest
	return valid_targets.pick_random()

func _attack(instance: EffectInstance, hit_report: HitReportData, killed_unit: Unit, target: Unit, killer: Unit) -> void:
	#generate payload
	var hit_data: HitData = projectile_data.generate_generic_hit_data()

	hit_data.source = killer
	hit_data.target = target
	hit_data.damage = killed_unit.get_stat(Attributes.id.MAX_HEALTH) * 0.2
	hit_data.target_affiliation = true #hostile
	if not hit_data.derive_lineage_from(hit_report, instance):
		return

	#configure delivery
	var delivery_data := projectile_data.generate_generic_delivery_data()

	#use source position override (dead unit's body)
	delivery_data.use_source_position_override = true
	delivery_data.source_position = killed_unit.global_position
	delivery_data.intercept_position = target.global_position

	await Clock.await_game_time(delay)
	CombatManager.resolve_hit(hit_data, delivery_data)
