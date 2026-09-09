extends EffectPrototype
class_name AmethystSkullEffect

#--- configuration ---
@export var search_radius: float = 200.0
@export var required_status: Attributes.Status = Attributes.Status.CURSED
@export var damage_multiplier: float = 0.0
@export var projectile_data: AttackData ##defines the spirit/bolt visual and speed
@export var delay: float = 0.2 ##delay in seconds between the triggering hit and the follow-up bolt

func _init() -> void: ##registers the skull as a global hit-reaction effect
	#the skull reacts before the original hit finishes resolving, so it can scale from the incoming damage payload
	event_hooks = [GameEvent.EventType.HIT_RECEIVED]
	global = true

#--- instance factory ---
func create_instance() -> EffectInstance: ##creates a stateless global effect instance
	var instance := EffectInstance.new()
	apply_generics(instance)
	return instance

#--- logic handlers ---

func _handle_attach(_instance: EffectInstance) -> void: ##amethyst skull has no attach-time runtime state
	pass

func _handle_detach(_instance: EffectInstance) -> void: ##amethyst skull has no detach-time runtime state
	pass

func _handle_event(instance: EffectInstance, event: GameEvent) -> void: ##fires a secondary bolt when a cursed enemy receives positive damage
	if event.event_type != GameEvent.EventType.HIT_RECEIVED:
		return

	var victim: Unit = event.unit
	if not is_instance_valid(victim) or not victim.hostile:
		return

	var trigger_hit: HitData = event.data as HitData
	if not trigger_hit or trigger_hit.negate or trigger_hit.damage <= 0.0:
		return

	if not is_instance_valid(victim.modifiers_component):
		return
	if not victim.modifiers_component.has_status(required_status):
		return

	if projectile_data == null:
		push_warning("AmethystSkullEffect: triggered but no projectile_data assigned.")
		return

	var target: Unit = _find_cursed_target(victim)

	if target:
		_attack(instance, trigger_hit, victim, target)

func _find_cursed_target(origin_unit: Unit) -> Unit: ##finds a nearby cursed enemy other than the unit that triggered the skull
	#get all enemies in range
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

func _attack(instance: EffectInstance, trigger_hit: HitData, origin_unit: Unit, target: Unit) -> void: ##derives a non-primary armor-piercing bolt from the original hit lineage
	#generate payload
	var hit_data: HitData = projectile_data.generate_generic_hit_data()

	hit_data.source = trigger_hit.get_source_unit()
	hit_data.target = target
	hit_data.damage = trigger_hit.damage * damage_multiplier * _get_effect_stacks(instance)
	hit_data.armour_ignore = 1.0
	hit_data.target_affiliation = true #hostile
	if not hit_data.derive_lineage_from(trigger_hit, instance):
		return
	hit_data.attack_id = AttackComponent.get_next_attack_id()
	hit_data.primary = false

	#configure delivery
	var delivery_data := projectile_data.generate_generic_delivery_data()

	#use source position override (dead unit's body)
	delivery_data.use_source_position_override = true
	delivery_data.source_position = origin_unit.global_position
	delivery_data.intercept_position = target.global_position

	await Clock.await_game_time(delay)
	if not is_instance_valid(instance) or not instance.enabled or not is_instance_valid(target):
		return
	CombatManager.resolve_hit(hit_data, delivery_data)

func _get_effect_stacks(instance: EffectInstance) -> int: ##keeps duplicate relic stacks multiplicative with the authored bolt damage
	return maxi(instance.stacks, 1)
