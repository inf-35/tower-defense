extends EventData
class_name HitData #stores information about a hit (runtime)

var negate: bool = false ##if set true, this hit is not processed
var attack_id: int = 0 ##positive when this hit belongs to one proc-countable hit group
var primary: bool = true ##when false, this hit is a child/follow-up payload and should not count as the source unit's primary attack trigger

var source: Unit ##dealer of hit
var target: Unit ##receiver of hit
var target_affiliation: bool ##affiliation of target (true for hostile, false for allied)
#NOTE: this is mainly for targetless hits with no predestined receiver. it will be overwritten
#if target exists (with the primary target's affiliation)

var damage: float = 0.0:
	set(nd):
		damage = nd
		expected_damage = damage #link expected damage and damage
var radius: float = 0.0 ##AOE effect range of the hit
var armour_ignore: float = 0.0 ##payload-local fraction of negative flat damage taken ignored by this hit
var breaking: bool = false ##can this hit damage shields?
var modifiers: Array[Modifier] = []
var status_effects: Dictionary[Attributes.Status, Vector2] = {} ##Attributes.Status -> Vector2(stack, cooldown)

var expected_damage: float = 0.0 ##see TargetingCoordinator, projected amount of damage caused


var velocity: Vector2 ##instantaneous velocity of the projectile, set by combatmanager

var vfx_on_spawn: VFXInfo #see VFXManager and VFXInstance
var vfx_on_impact: VFXInfo
var fire_sound: StringName = &"" ##optional sound id played when this attack payload is fired
var hit_sound: StringName = ID.Sounds.ENEMY_HIT_SOUND ##sound id played when this attack payload hits an enemy
var projectile_tints: Array[Color] = [] ##ordered tint palette cycled across the base projectile visual while it is in flight
#see unit.gd, deal_hit and take_hit and AttackData

func duplicate() -> EventData: ##copies the fixed hit payload directly so high-volume aoes avoid reflective property discovery
	var hit_copy := HitData.new()
	hit_copy.recursion = recursion
	hit_copy.lineage = lineage.duplicate()
	hit_copy.negate = negate
	hit_copy.attack_id = attack_id
	hit_copy.primary = primary
	hit_copy.source = source if is_instance_valid(source) else null
	hit_copy.target = target if is_instance_valid(target) else null
	hit_copy.target_affiliation = target_affiliation
	hit_copy.damage = damage
	hit_copy.expected_damage = expected_damage
	hit_copy.radius = radius
	hit_copy.armour_ignore = armour_ignore
	hit_copy.breaking = breaking
	hit_copy.modifiers = modifiers.duplicate(true)
	hit_copy.status_effects = status_effects.duplicate(true)
	hit_copy.velocity = velocity
	hit_copy.vfx_on_spawn = vfx_on_spawn
	hit_copy.vfx_on_impact = vfx_on_impact
	hit_copy.fire_sound = fire_sound
	hit_copy.hit_sound = hit_sound
	hit_copy.projectile_tints = projectile_tints.duplicate()
	return hit_copy

static func consume_attack_id(hit_data: HitData, seen_attack_ids: Dictionary[int, bool]) -> bool: ##returns true once per proc group in the supplied effect-local seen table
	if not hit_data or hit_data.attack_id <= 0:
		return false

	if seen_attack_ids.has(hit_data.attack_id):
		return false

	seen_attack_ids[hit_data.attack_id] = true
	return true
